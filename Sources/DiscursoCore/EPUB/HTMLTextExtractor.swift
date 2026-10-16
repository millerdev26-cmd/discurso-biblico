//
//  HTMLTextExtractor.swift
//  DiscursoCore
//
//  Extração de texto de HTML/XHTML.
//
//  Usada para:
//   - ler capítulos de EPUB (que são XHTML);
//   - indexar materiais importados para pesquisa local;
//   - montar um sumário alternativo quando o EPUB não traz navegação.
//
//  Não é um navegador: interpreta apenas marcação estrutural e entidades de
//  caractere, o suficiente para leitura e busca. Scripts e estilos são
//  descartados.
//

import Foundation

/// Resultado da extração de texto de um documento HTML/XHTML.
public struct HTMLTextExtraction: Hashable, Sendable {
    /// Título do documento (`<title>`), quando houver.
    public var title: String?
    /// Texto corrido, com quebras de linha preservando parágrafos.
    public var text: String
    /// Títulos internos (`<h1>`...`<h6>`) com a posição no texto extraído.
    public var headings: [HTMLHeading]
    /// Parágrafos na ordem em que aparecem.
    public var paragraphs: [String]

    public init(
        title: String? = nil,
        text: String = "",
        headings: [HTMLHeading] = [],
        paragraphs: [String] = []
    ) {
        self.title = title
        self.text = text
        self.headings = headings
        self.paragraphs = paragraphs
    }
}

/// Título interno de um documento HTML.
public struct HTMLHeading: Hashable, Sendable {
    /// Nível do título (1...6).
    public var level: Int
    public var text: String
    /// Deslocamento em caracteres dentro do texto extraído.
    public var characterOffset: Int

    public init(level: Int, text: String, characterOffset: Int) {
        self.level = level
        self.text = text
        self.characterOffset = characterOffset
    }
}

public enum HTMLTextExtractor {

    /// Tags que iniciam um novo bloco de texto.
    private static let blockTags: Set<String> = [
        "p", "div", "br", "section", "article", "header", "footer", "aside",
        "blockquote", "table", "tr", "td", "th", "ul", "ol", "dl", "dt", "dd",
        "hr", "figure", "figcaption", "pre", "form", "nav", "main", "h1", "h2",
        "h3", "h4", "h5", "h6", "title", "body"
    ]

    /// Tags cujo conteúdo deve ser ignorado.
    private static let ignoredTags: Set<String> = ["script", "style", "head", "meta", "link", "svg", "noscript"]

    /// Extrai texto e estrutura de um documento HTML/XHTML.
    ///
    /// - Parameter includeTitle: quando `true`, o conteúdo de `<title>` entra
    ///   no texto extraído (útil para indexação).
    public static func extract(from html: String, includeTitle: Bool = false) -> HTMLTextExtraction {
        var output = ""
        var paragraphs: [String] = []
        var headings: [HTMLHeading] = []
        var title: String?
        var currentParagraph = ""
        var ignoreUntilClose: String?
        var headingStartLevel: Int?

        let characters = Array(html)
        var index = 0

        func flushParagraph() {
            let trimmed = collapseWhitespace(currentParagraph).trimmingCharacters(in: .whitespacesAndNewlines)
            currentParagraph = ""
            guard !trimmed.isEmpty else { return }
            paragraphs.append(trimmed)
            if !output.isEmpty, !output.hasSuffix("\n\n") {
                output += output.hasSuffix("\n") ? "\n" : "\n\n"
            }
            output += trimmed
        }

        while index < characters.count {
            let character = characters[index]

            // Comentários, CDATA e declarações
            if character == "<", index + 3 < characters.count, characters[index + 1] == "!" {
                let prefix = String(characters[index..<min(index + 9, characters.count)])
                if prefix.hasPrefix("<!--") {
                    if let end = find("-->", from: index + 4, in: characters) {
                        index = end + 3
                        continue
                    }
                    break
                }
                if prefix.hasPrefix("<![CDATA[") {
                    if let end = find("]]>", from: index + 9, in: characters) {
                        currentParagraph += String(characters[(index + 9)..<end])
                        index = end + 3
                        continue
                    }
                    break
                }
                if let end = find(">", from: index + 1, in: characters) {
                    index = end + 1
                    continue
                }
                index += 1
                continue
            }

            // Tags
            if character == "<" {
                guard let closeIndex = findTagEnd(from: index + 1, in: characters) else {
                    index += 1
                    continue
                }
                let rawTag = String(characters[(index + 1)..<closeIndex])
                index = closeIndex + 1

                let parsed = parseTag(rawTag)

                // O título do documento é capturado mesmo dentro de <head>,
                // porque é útil para nomear o material importado.
                if parsed.name == "title" {
                    if !parsed.isClosing,
                       let end = findTag(named: "title", from: index, in: characters) {
                        title = decodeEntities(String(characters[index..<end]))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if includeTitle { currentParagraph += " " + (title ?? "") }
                        index = end
                    }
                    continue
                }

                if let ignored = ignoreUntilClose {
                    if parsed.name == ignored, parsed.isClosing { ignoreUntilClose = nil }
                    continue
                }
                if ignoredTags.contains(parsed.name), !parsed.isSelfClosing {
                    if !parsed.isClosing { ignoreUntilClose = parsed.name }
                    continue
                }

                let headingLevel = headingLevel(of: parsed.name)
                if let headingLevel {
                    if parsed.isClosing {
                        flushParagraph()
                    } else {
                        flushParagraph()
                        headingStartLevel = headingLevel
                    }
                    continue
                }

                if parsed.name == "li", !parsed.isClosing, !parsed.isSelfClosing {
                    flushParagraph()
                    currentParagraph += "• "
                    continue
                }

                if blockTags.contains(parsed.name) {
                    flushParagraph()
                    continue
                }
                continue
            }

            // Texto
            if ignoreUntilClose != nil {
                // Dentro de <script>/<style>/<head>: nada é aproveitado.
                index += 1
                continue
            }

            if let level = headingStartLevel {
                // Coleta o título até a tag de fechamento correspondente.
                if let end = findTag(named: "h\(level)", from: index, in: characters) {
                    let raw = String(characters[index..<end])
                    let text = collapseWhitespace(decodeEntities(stripTags(raw)))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    flushParagraph()
                    if !text.isEmpty {
                        headings.append(HTMLHeading(level: level, text: text, characterOffset: output.count))
                        currentParagraph = text
                    }
                    headingStartLevel = nil
                    index = end
                    continue
                }
                headingStartLevel = nil
            }

            if character == "&", let (decoded, consumed) = decodeEntity(at: index, in: characters) {
                currentParagraph += decoded
                index += consumed
                continue
            }

            currentParagraph.append(character)
            index += 1
        }

        flushParagraph()

        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return HTMLTextExtraction(title: title, text: cleaned, headings: headings, paragraphs: paragraphs)
    }

    /// Nível do título quando a tag é h1...h6.
    private static func headingLevel(of tagName: String) -> Int? {
        guard tagName.count == 2, tagName.hasPrefix("h"),
              let level = Int(String(tagName.suffix(1))), (1...6).contains(level)
        else { return nil }
        return level
    }

    /// Texto simples de um fragmento HTML (usado no editor e na exportação).
    public static func plainText(from html: String) -> String {
        extract(from: html).text
    }

    /// Remove tags de um fragmento, sem decodificar entidades.
    public static func stripTags(_ html: String) -> String {
        var result = ""
        var insideTag = false
        for character in html {
            if character == "<" { insideTag = true; continue }
            if character == ">" { insideTag = false; continue }
            if !insideTag { result.append(character) }
        }
        return result
    }

    // MARK: - Utilitários de leitura

    private struct ParsedTag {
        var name: String
        var isClosing: Bool
        var isSelfClosing: Bool
    }

    private static func parseTag(_ rawTag: String) -> ParsedTag {
        var text = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        var isClosing = false
        if text.hasPrefix("/") {
            isClosing = true
            text.removeFirst()
        }
        let isSelfClosing = text.hasSuffix("/")
        if isSelfClosing { text.removeLast() }
        let name = text
            .prefix { !$0.isWhitespace && $0 != "/" }
            .lowercased()
        return ParsedTag(name: name, isClosing: isClosing, isSelfClosing: isSelfClosing)
    }

    /// Encontra o fim de uma tag, respeitando aspas em atributos.
    private static func findTagEnd(from start: Int, in characters: [Character]) -> Int? {
        var index = start
        var quote: Character?
        while index < characters.count {
            let character = characters[index]
            if let currentQuote = quote {
                if character == currentQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func find(_ needle: String, from start: Int, in characters: [Character]) -> Int? {
        let needleCharacters = Array(needle)
        guard !needleCharacters.isEmpty else { return nil }
        var index = start
        while index + needleCharacters.count <= characters.count {
            var matches = true
            for offset in 0..<needleCharacters.count where characters[index + offset] != needleCharacters[offset] {
                matches = false
                break
            }
            if matches { return index }
            index += 1
        }
        return nil
    }

    /// Encontra a posição da tag de fechamento informada (usada em `<title>`).
    private static func findTag(named name: String, from start: Int, in characters: [Character]) -> Int? {
        let needle = "</\(name)"
        let lowercased = characters.map { Character(String($0).lowercased()) }
        return find(needle, from: start, in: lowercased)
    }

    // MARK: - Entidades

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "mdash": "—", "ndash": "–", "hellip": "…", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "laquo": "«", "raquo": "»", "bull": "•",
        "middot": "·", "deg": "°", "copy": "©", "reg": "®", "trade": "™", "euro": "€",
        "aacute": "á", "Aacute": "Á", "acirc": "â", "agrave": "à", "atilde": "ã", "auml": "ä",
        "eacute": "é", "Eacute": "É", "ecirc": "ê", "egrave": "è", "iacute": "í", "Iacute": "Í",
        "oacute": "ó", "Oacute": "Ó", "ocirc": "ô", "otilde": "õ", "uacute": "ú", "Uacute": "Ú",
        "ccedil": "ç", "Ccedil": "Ç", "ordm": "º", "ordf": "ª", "sect": "§", "para": "¶",
        "frac12": "½", "times": "×", "minus": "−", "prime": "′", "Prime": "″"
    ]

    private static func decodeEntity(at index: Int, in characters: [Character]) -> (String, Int)? {
        var cursor = index + 1
        var body = ""
        while cursor < characters.count, body.count <= 12 {
            let character = characters[cursor]
            if character == ";" {
                guard !body.isEmpty else { return nil }
                if body.hasPrefix("#") {
                    let numberText = String(body.dropFirst())
                    let value: UInt32?
                    if numberText.hasPrefix("x") || numberText.hasPrefix("X") {
                        value = UInt32(numberText.dropFirst(), radix: 16)
                    } else {
                        value = UInt32(numberText)
                    }
                    if let value, let scalar = Unicode.Scalar(value) {
                        return (String(Character(scalar)), cursor - index + 1)
                    }
                    return nil
                }
                if let replacement = namedEntities[body] {
                    return (replacement, cursor - index + 1)
                }
                // Entidade desconhecida: mantém como está.
                return (String(characters[index...cursor]), cursor - index + 1)
            }
            if character == " " || character == "<" || character == "&" || character == "\n" { return nil }
            body.append(character)
            cursor += 1
        }
        return nil
    }

    /// Decodifica entidades em um texto inteiro.
    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index] == "&", let (decoded, consumed) = decodeEntity(at: index, in: characters) {
                result += decoded
                index += consumed
            } else {
                result.append(characters[index])
                index += 1
            }
        }
        return result
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var result = ""
        var lastWasSpace = false
        for character in text {
            if character == "\n" {
                result.append("\n")
                lastWasSpace = true
                continue
            }
            if character.isWhitespace || character == "\u{00A0}" {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }
        return result
    }
}
