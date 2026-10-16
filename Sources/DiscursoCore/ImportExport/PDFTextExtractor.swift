//
//  PDFTextExtractor.swift
//  DiscursoCore
//
//  Extração de texto de PDF para indexação local — implementação mínima.
//
//  IMPORTANTE (limitações, ver `docs/LIMITACOES.md`):
//   - No aplicativo iOS, a leitura e a indexação de PDF usam o **PDFKit**
//     (implementação `PDFKitTextExtracting`, na camada do aplicativo), que
//     interpreta fontes, codificações e páginas corretamente.
//   - Este extrator puro em Swift é a alternativa usada nos testes deste
//     repositório (Linux) e como último recurso quando o PDFKit não puder
//     ser usado. Ele lê fluxos de conteúdo com `Tj`/`TJ`/`'`/`"` e
//     `/FlateDecode`, sem interpretar CMap/fontes embutidas; PDFs com
//     codificações exóticas podem sair ilegíveis.
//   - Nenhum PDF protegido é processado: quando há `/Encrypt`, a importação
//     recusa o arquivo (a menos que o usuário escolha mantê-lo só como
//     referência, sem indexação).
//

import Foundation

/// Texto extraído de um PDF, por página.
public struct PDFExtraction: Sendable {
    /// Texto de cada página, na ordem.
    public var pages: [String]
    /// `true` quando o arquivo declara criptografia.
    public var isEncrypted: Bool
    /// Avisos (ex.: fluxos que não puderam ser lidos).
    public var warnings: [String]

    public init(pages: [String] = [], isEncrypted: Bool = false, warnings: [String] = []) {
        self.pages = pages
        self.isEncrypted = isEncrypted
        self.warnings = warnings
    }

    public var fullText: String {
        pages.joined(separator: "\n\n")
    }
}

/// Extrator mínimo de texto de PDF em Swift puro.
public enum PDFTextExtractor {

    /// Detecta a presença de criptografia declarada (`/Encrypt`).
    ///
    /// A verificação varre o final do arquivo (onde fica o `trailer`), com um
    /// limite generoso para arquivos que usam stream de atualização.
    public static func isEncrypted(data: Data) -> Bool {
        // Sem material de proteção, nenhum conteúdo é decodificado.
        let window = data.count > 2_000_000 ? data.suffix(2_000_000) : data
        guard let text = String(data: window, encoding: .isoLatin1) else { return false }
        return text.contains("/Encrypt")
    }

    /// Extrai o texto das páginas.
    public static func extract(data: Data) -> PDFExtraction {
        var extraction = PDFExtraction()
        extraction.isEncrypted = isEncrypted(data: data)

        let bytes = [UInt8](data)
        var index = 0
        var pageIndex = 0

        while index < bytes.count {
            guard let streamRange = findStream(from: index, in: bytes) else { break }

            // Dicionário imediatamente antes de `stream`.
            let dictionary = dictionary(before: streamRange.streamKeyword, in: bytes)
            let isFlate = dictionary?.uppercased().contains("FLATEDECODE") ?? false
            let isImage = dictionary?.uppercased().contains("IMAGE") ?? false

            var payload = Data(bytes[streamRange.dataStart..<streamRange.dataEnd])
            if isFlate {
                if let inflated = try? Inflate.decompressZlib(payload) {
                    payload = inflated
                } else {
                    extraction.warnings.append("Fluxo de página \(pageIndex + 1) não pôde ser descompactado.")
                }
            }

            if !isImage, let text = extractText(fromContentStream: [UInt8](payload)) {
                extraction.pages.append(text)
                pageIndex += 1
            }
            // Fluxos sem texto (imagens, fontes embutidas) são simplesmente
            // ignorados: a indexação não depende deles.
            index = streamRange.dataEnd + "endstream".count + 2
        }

        return extraction
    }

    // MARK: - Fluxos

    private struct StreamRange {
        var streamKeyword: Int
        var dataStart: Int
        var dataEnd: Int
    }

    private static func findStream(from start: Int, in bytes: [UInt8]) -> StreamRange? {
        let needle = Array("stream".utf8)
        var index = max(0, start)
        while index + needle.count < bytes.count {
            guard matches(needle, at: index, in: bytes) else {
                index += 1
                continue
            }
            var dataStart = index + needle.count
            // CRLF ou LF
            if dataStart < bytes.count, bytes[dataStart] == 13 { dataStart += 1 }
            if dataStart < bytes.count, bytes[dataStart] == 10 { dataStart += 1 }

            guard let end = findEndstream(from: dataStart, in: bytes) else { return nil }
            var dataEnd = end
            // Remove a quebra de linha antes de `endstream`.
            while dataEnd > dataStart, bytes[dataEnd - 1] == 10 || bytes[dataEnd - 1] == 13 {
                dataEnd -= 1
            }
            return StreamRange(streamKeyword: index, dataStart: dataStart, dataEnd: dataEnd)
        }
        return nil
    }

    private static func findEndstream(from start: Int, in bytes: [UInt8]) -> Int? {
        let needle = Array("endstream".utf8)
        var index = max(0, start)
        while index + needle.count <= bytes.count {
            if matches(needle, at: index, in: bytes) { return index }
            index += 1
        }
        return nil
    }

    private static func matches(_ needle: [UInt8], at index: Int, in bytes: [UInt8]) -> Bool {
        guard index >= 0, index + needle.count <= bytes.count else { return false }
        for offset in 0..<needle.count where bytes[index + offset] != needle[offset] {
            return false
        }
        return true
    }

    /// Dicionário (`<< ... >>`) que precede a palavra `stream`.
    private static func dictionary(before streamKeyword: Int, in bytes: [UInt8]) -> String? {
        let searchStart = max(0, streamKeyword - 4000)
        let slice = Array(bytes[searchStart..<streamKeyword])
        guard let doubleClose = lastOccurrence(of: Array(">>".utf8), in: slice) else { return nil }
        guard let doubleOpen = lastOccurrence(of: Array("<<".utf8), in: Array(slice[0..<doubleClose])) else { return nil }
        return String(bytes: slice[doubleOpen..<doubleClose], encoding: .isoLatin1)
    }

    private static func lastOccurrence(of needle: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= needle.count else { return nil }
        var index = bytes.count - needle.count
        while index >= 0 {
            if matches(needle, at: index, in: bytes) { return index }
            index -= 1
        }
        return nil
    }

    // MARK: - Operadores de texto

    /// Extrai o texto de um fluxo de conteúdo PDF.
    ///
    /// Estratégia: dentro de `BT ... ET`, coleta cadeias de texto nas formas
    /// `(...) Tj`, `[ ... ] TJ` (com ajustes de espaçamento) e `(...) '`/`"`.
    private static func extractText(fromContentStream bytes: [UInt8]) -> String? {
        var pieces: [String] = []
        var index = 0
        var lastWasGap = true

        while index < bytes.count {
            let byte = bytes[index]

            if byte == 0x28 { // "("
                guard let (text, next) = readLiteralString(from: bytes, at: index) else { break }
                if !text.isEmpty {
                    if !lastWasGap, !pieces.isEmpty { pieces.append(" ") }
                    pieces.append(text)
                    lastWasGap = false
                }
                index = next
                continue
            }

            if byte == 0x5B { // "[" — possível array TJ
                if let (texts, next) = readArray(from: bytes, at: index) {
                    for (textIndex, text) in texts.enumerated() {
                        if textIndex > 0, let nextText = texts[safe: textIndex], !nextText.isEmpty {
                            pieces.append(" ")
                        }
                        if !text.isEmpty { pieces.append(text) }
                    }
                    index = next
                    lastWasGap = false
                    continue
                }
            }

            if byte == 0x54 || byte == 0x27 || byte == 0x22 { // T, ', "
                // Operadores Tj, TJ, ', " — apenas registra separação visual.
                if byte == 0x27 || byte == 0x22 {
                    if !pieces.isEmpty { pieces.append("\n") }
                }
                index += 1
                lastWasGap = true
                continue
            }

            if byte == 0x0A || byte == 0x0D { // quebras em fluxos simples
                lastWasGap = true
                index += 1
                continue
            }

            index += 1
        }

        guard !pieces.isEmpty else { return nil }
        let text = pieces.joined()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Lê uma cadeia literal `( ... )`, com escapes PDF.
    private static func readLiteralString(from bytes: [UInt8], at start: Int) -> (String, Int)? {
        var index = start + 1
        var depth = 1
        var out: [UInt8] = []
        var escaped = false

        while index < bytes.count {
            let byte = bytes[index]
            if escaped {
                switch byte {
                case 0x6E: out.append(0x0A) // \n
                case 0x72: out.append(0x0D) // \r
                case 0x74: out.append(0x09) // \t
                case 0x62, 0x66: break     // \b \f
                case 0x28, 0x29, 0x5C: out.append(byte)
                case 0x30...0x37:          // octal \nnn
                    var value = Int(byte - 0x30)
                    var extra = 0
                    while extra < 2, index + 1 < bytes.count, (0x30...0x37).contains(bytes[index + 1]) {
                        index += 1
                        value = value * 8 + Int(bytes[index] - 0x30)
                        extra += 1
                    }
                    out.append(UInt8(truncatingIfNeeded: value))
                default: out.append(byte)
                }
                escaped = false
                index += 1
                continue
            }

            switch byte {
            case 0x5C: escaped = true
            case 0x28: depth += 1; out.append(byte)
            case 0x29:
                depth -= 1
                if depth == 0 {
                    return (decodePDFBytes(out), index + 1)
                }
                out.append(byte)
            default: out.append(byte)
            }
            index += 1
        }
        return nil
    }

    /// Lê um array `[ ... ]` de cadeias de texto (usado em `TJ`).
    private static func readArray(from bytes: [UInt8], at start: Int) -> ([String], Int)? {
        var index = start + 1
        var texts: [String] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x5D { // "]"
                return (texts, index + 1)
            }
            if byte == 0x28 {
                guard let (text, next) = readLiteralString(from: bytes, at: index) else { return nil }
                texts.append(text)
                index = next
                continue
            }
            // Números (ajustes de espaçamento) são ignorados; valores entre
            // -100 e -600 costumam indicar espaço — aproximamos por espaço.
            index += 1
        }
        return nil
    }

    /// Converte bytes de uma cadeia PDF em texto. PDFDocEncoding/Windows-1252
    /// são próximos de Latin-1 para os caracteres usados em português.
    private static func decodePDFBytes(_ bytes: [UInt8]) -> String {
        // Marcas de ordem de bytes (UTF-16) em cadeias de texto.
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            return String(data: Data(bytes.dropFirst(2)), encoding: .utf16BigEndian) ?? ""
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            return String(data: Data(bytes.dropFirst(2)), encoding: .utf16LittleEndian) ?? ""
        }
        return String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        indices.contains(index) ? self[index] : nil
    }
}
