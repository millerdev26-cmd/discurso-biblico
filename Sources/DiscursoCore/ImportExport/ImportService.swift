//
//  ImportService.swift
//  DiscursoCore
//
//  Importação de materiais para a biblioteca pessoal.
//
//  Antes de gravar qualquer coisa, o arquivo passa por uma triagem:
//
//   1. extensão reconhecida (EPUB, PDF, TXT, Markdown, HTML; DOCX/JWPUB são
//      aceitos como "sem suporte de leitura" e ficam identificados assim);
//   2. tamanho mínimo/máximo;
//   3. assinatura do conteúdo (ZIP para EPUB, "%PDF-" para PDF, texto válido
//      para TXT/Markdown/HTML);
//   4. proteção de conteúdo (DRM) — declarada no pacote, nunca contornada;
//   5. hash do conteúdo, para reconhecer duplicados já importados.
//
//  A triagem informa o resultado com mensagens prontas para o usuário, e o
//  item só é criado quando o material é considerado válido (ou quando o
//  usuário escolhe manter um formato ainda sem leitura).
//

import Foundation

/// Erros de importação, com mensagens em português.
public enum ImportError: LocalizedError, Equatable {
    /// Extensão desconhecida.
    case unsupportedExtension(String)
    /// Formato conhecido, mas sem suporte de leitura (ex.: DOCX, JWPUB).
    case formatNotSupported(String)
    /// Arquivo vazio.
    case emptyFile
    /// Arquivo maior que o limite configurado.
    case fileTooLarge(size: Int64, limit: Int64)
    /// Conteúdo não corresponde ao formato esperado (corrompido).
    case invalidContent(reason: String)
    /// Conteúdo protegido (DRM).
    case protectedContent(format: String)
    /// O arquivo informado não pôde ser lido.
    case unreadableFile(reason: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let name):
            return "O arquivo “\(name)” não está em um formato reconhecido."
        case .formatNotSupported(let name):
            return "O formato “\(name)” ainda não pode ser lido dentro do aplicativo."
        case .emptyFile:
            return "O arquivo está vazio."
        case .fileTooLarge(let size, let limit):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "O arquivo tem \(formatter.string(fromByteCount: size)) e o limite é \(formatter.string(fromByteCount: limit))."
        case .invalidContent(let reason):
            return "O arquivo parece estar corrompido ou incompleto: \(reason)."
        case .protectedContent(let format):
            return "O \(format) importado é protegido (DRM). O aplicativo não remove proteções de conteúdo."
        case .unreadableFile(let reason):
            return "Não foi possível ler o arquivo: \(reason)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .formatNotSupported:
            return "Você ainda pode manter o arquivo na biblioteca como referência, ou convertê-lo para PDF, EPUB, TXT ou Markdown."
        case .protectedContent:
            return "Use o aplicativo oficial do fornecedor para abrir este arquivo, ou importe uma versão sem proteção."
        case .invalidContent:
            return "Baixe o arquivo novamente ou verifique se a cópia está completa."
        case .fileTooLarge:
            return "Materiais muito grandes podem ser divididos em partes menores."
        default:
            return nil
        }
    }
}

/// Avisos (não fatais) da importação.
public enum ImportWarning: Equatable, Sendable {
    /// O arquivo continua na biblioteca, mas não pode ser lido no aplicativo.
    case formatWithoutReader(String)
    /// O arquivo é protegido; foi mantido, mas não será indexado.
    case protectedContentKept(String)

    public var message: String {
        switch self {
        case .formatWithoutReader(let kind):
            return "O material foi guardado na biblioteca, mas o formato \(kind) ainda não pode ser lido dentro do aplicativo."
        case .protectedContentKept(let format):
            return "O \(format) é protegido (DRM): foi guardado como referência e não será indexado. Use o aplicativo oficial do fornecedor para ler."
        }
    }
}

/// Resultado da triagem de um arquivo.
public struct PreparedImport: Sendable {
    /// Item pronto para ser gravado (sem o arquivo ainda).
    public var item: LibraryItem
    /// Avisos que devem ser mostrados ao usuário.
    public var warnings: [ImportWarning]
    /// Item já existente com o mesmo conteúdo, quando houver.
    public var duplicateOf: UUID?

    public var isDuplicate: Bool { duplicateOf != nil }
}

/// Configuração da triagem de importação.
public struct ImportPolicy: Sendable {
    /// Tamanho máximo aceito (padrão: 200 MB).
    public var maximumFileSize: Int64
    /// Guarda formatos sem leitura (DOCX/JWPUB) como itens "sem suporte".
    public var storesUnsupportedFormats: Bool
    /// Permite importar conteúdo protegido apenas como referência.
    public var keepsProtectedContent: Bool

    public static let `default` = ImportPolicy()

    public init(
        maximumFileSize: Int64 = 200 * 1024 * 1024,
        storesUnsupportedFormats: Bool = true,
        keepsProtectedContent: Bool = false
    ) {
        self.maximumFileSize = maximumFileSize
        self.storesUnsupportedFormats = storesUnsupportedFormats
        self.keepsProtectedContent = keepsProtectedContent
    }
}

/// Triagem e preparação de arquivos importados.
public enum ImportService {

    /// Classifica um arquivo pela extensão.
    public static func classify(fileName: String) -> LibraryItemKind? {
        let fileExtension = (fileName as NSString).pathExtension
        guard !fileExtension.isEmpty else { return nil }
        return LibraryItemKind.from(fileExtension: fileExtension)
    }

    /// Triagem completa: valida o conteúdo e monta o item da biblioteca.
    ///
    /// - Parameters:
    ///   - data: conteúdo do arquivo já lido.
    ///   - originalFileName: nome original (usado no título e na extensão).
    ///   - existingItems: itens já importados (para detectar duplicados).
    ///   - policy: limites e tolerâncias da importação.
    public static func prepare(
        data: Data,
        originalFileName: String,
        titleOverride: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        sourceURL: URL? = nil,
        existingItems: [LibraryItem] = [],
        policy: ImportPolicy = .default,
        now: Date = Date()
    ) throws -> PreparedImport {
        let fileName = originalFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else {
            throw ImportError.unsupportedExtension("arquivo sem nome")
        }
        guard let kind = classify(fileName: fileName) else {
            throw ImportError.unsupportedExtension(fileName)
        }

        guard !data.isEmpty else { throw ImportError.emptyFile }
        guard Int64(data.count) <= policy.maximumFileSize else {
            throw ImportError.fileTooLarge(size: Int64(data.count), limit: policy.maximumFileSize)
        }

        if kind == .unsupported, !policy.storesUnsupportedFormats {
            throw ImportError.formatNotSupported((fileName as NSString).pathExtension.uppercased())
        }

        var warnings: [ImportWarning] = []
        var isProtected = false

        switch kind {
        case .epub:
            try validateZIPSignature(data)
            switch EPUBParser.protectionStatus(in: data) {
            case .protectedContent:
                if policy.keepsProtectedContent {
                    isProtected = true
                    warnings.append(.protectedContentKept("EPUB"))
                } else {
                    throw ImportError.protectedContent(format: "EPUB")
                }
            case .unknown:
                throw ImportError.invalidContent(reason: "o pacote EPUB não pôde ser lido")
            case .unprotected:
                break
            }
        case .pdf:
            try validatePDF(data)
            if PDFTextExtractor.isEncrypted(data: data) {
                if policy.keepsProtectedContent {
                    isProtected = true
                    warnings.append(.protectedContentKept("PDF"))
                } else {
                    throw ImportError.protectedContent(format: "PDF")
                }
            }
        case .plainText, .markdown, .html:
            guard TextFileDecoder.decode(data) != nil else {
                throw ImportError.invalidContent(reason: "o conteúdo não é texto legível")
            }
        case .unsupported:
            warnings.append(.formatWithoutReader((fileName as NSString).pathExtension.uppercased()))
        }

        let hash = contentHash(of: data)
        let duplicate = existingItems.first { item in
            item.contentHash == hash && item.fileSize == Int64(data.count)
        }

        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        let itemID = UUID()
        let title = titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false ? title! : nil)
            ?? suggestedTitle(fromFileName: fileName)

        let item = LibraryItem(
            id: itemID,
            title: resolvedTitle,
            author: nil,
            kind: kind,
            fileName: "\(itemID.uuidString).\(fileExtension.isEmpty ? "dat" : fileExtension)",
            fileExtension: fileExtension,
            fileSize: Int64(data.count),
            contentHash: hash,
            importedAt: now,
            lastOpenedAt: nil,
            category: category,
            tags: tags,
            isFavorite: false,
            indexStatus: kind == .unsupported ? .failed : .pending,
            indexFailureReason: kind == .unsupported
                ? "Formato ainda sem suporte de leitura."
                : nil,
            unitCount: nil,
            lastReadPosition: nil,
            notes: [],
            bookmarks: [],
            highlights: [],
            sourceURL: sourceURL,
            originalFileName: fileName,
            isProtected: isProtected
        )

        return PreparedImport(item: item, warnings: warnings, duplicateOf: duplicate?.id)
    }

    // MARK: - Validações

    private static func validateZIPSignature(_ data: Data) throws {
        guard data.count >= 4 else {
            throw ImportError.invalidContent(reason: "arquivo muito curto para ser um EPUB")
        }
        let signature: [UInt8] = [0x50, 0x4B] // "PK"
        guard [UInt8](data.prefix(2)) == signature else {
            throw ImportError.invalidContent(reason: "o arquivo não é um pacote ZIP (EPUB)")
        }
    }

    private static func validatePDF(_ data: Data) throws {
        // A especificação permite a assinatura em qualquer ponto dos
        // primeiros 1024 bytes (leitores tolerantes fazem isso).
        let window = data.prefix(1024)
        let signature: [UInt8] = Array("%PDF-".utf8)
        guard window.count >= signature.count else {
            throw ImportError.invalidContent(reason: "arquivo muito curto para ser um PDF")
        }
        let bytes = [UInt8](window)
        outer: for start in 0...(bytes.count - signature.count) {
            for offset in 0..<signature.count where bytes[start + offset] != signature[offset] {
                continue outer
            }
            return
        }
        throw ImportError.invalidContent(reason: "o arquivo não começa com a assinatura de PDF")
    }

    // MARK: - Utilitários

    /// Hash estável de conteúdo (FNV-1a de 64 bits), usado para duplicados.
    public static func contentHash(of data: Data) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "fnv1a64:%016llx", hash)
    }

    /// Título provisório a partir do nome do arquivo.
    public static func suggestedTitle(fromFileName fileName: String) -> String {
        let withoutExtension = (fileName as NSString).deletingPathExtension
        let cleaned = withoutExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return fileName }
        return cleaned
    }
}

/// Decodificação de arquivos de texto, tolerando as codificações comuns.
public enum TextFileDecoder {

    /// Decodifica textualmente, tentando UTF-8, UTF-16 e Latin-1.
    ///
    /// Devolve `nil` quando o conteúdo tem cara de binário (bytes nulos ou
    /// muitos caracteres de controle), o que indica arquivo corrompido.
    public static func decode(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let limited = data.prefix(200_000)

        var text: String?
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let utf16 = String(data: data, encoding: .utf16) {
            text = utf16
        } else if let latin = String(data: data, encoding: .isoLatin1) {
            text = latin
        }
        guard let decoded = text else { return nil }

        // Heurística de binário: bytes nulos ou mais de 5% de controles.
        guard decoded.unicodeScalars.allSatisfy({ scalar in
            scalar.value == 9 || scalar.value == 10 || scalar.value == 13 || scalar.value >= 32
        }) else { return nil }
        let sample = [UInt8](limited)
        if sample.contains(0) { return nil }

        return decoded
    }
}
