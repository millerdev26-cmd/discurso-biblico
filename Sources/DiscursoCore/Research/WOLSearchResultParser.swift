//
//  WOLSearchResultParser.swift
//  DiscursoCore
//
//  Leitura da página pública de resultados da Biblioteca On-line (WOL).
//
//  Estrutura observada na fonte pública (pt-BR):
//
//    <ul class="directory resultContentTopic">
//      <li class="caption"><a class="lnk" href="/pt/wol/d/r5/lp-t/…">Título</a></li>
//      <li class="result"><ul class="resultItems"><li class="ref">Publicação</li></ul></li>
//      <li class="resultSubheadings"><ul class="resultItems"><li><a href="…#p14">Trecho</a></li></ul></li>
//    </ul>
//
//  O parser é tolerante: se a marcação mudar, ele devolve o que conseguir e o
//  aplicativo mantém os links oficiais como alternativa. Páginas de desafio
//  (CAPTCHA) são reconhecidas e **não** são processadas.
//

import Foundation

/// Um resultado da página pública de pesquisa do WOL.
public struct WOLSearchResult: Hashable, Sendable {
    public var title: String
    /// Endereço absoluto (`https://wol.jw.org/...`).
    public var url: URL
    /// Publicação de origem ("A Sentinela", "Despertai!" etc.).
    public var publication: String?
    /// Trechos/anchor internos encontrados.
    public var subResults: [WOLSearchSubResult]

    public init(title: String, url: URL, publication: String? = nil, subResults: [WOLSearchSubResult] = []) {
        self.title = title
        self.url = url
        self.publication = publication
        self.subResults = subResults
    }
}

/// Sub-resultado (trecho interno de uma publicação).
public struct WOLSearchSubResult: Hashable, Sendable {
    public var title: String
    public var url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public enum WOLSearchResultParser {

    /// Página de desafio (CAPTCHA/verificação) — nunca deve ser interpretada.
    public static func looksBlocked(html: String) -> Bool {
        let lower = html.lowercased()
        let signals = [
            "g-recaptcha", "recaptcha/api", "cf-challenge", "cf_chl_opt",
            "captcha", "confirme que você é humano", "verifique que você é humano",
            "checking your browser", "attention required"
        ]
        return signals.contains { lower.contains($0) }
    }

    /// Devolve `true` quando a página parece não ter resultados.
    public static func looksEmpty(html: String) -> Bool {
        let lower = html.lowercased()
        return !lower.contains("resultcontenttopic")
    }

    /// Extrai os resultados da página pública.
    ///
    /// - Parameter baseURL: usada para resolver endereços relativos
    ///   (`/pt/wol/d/…`). Padrão: o próprio host oficial do WOL.
    public static func parse(html: String, baseURL: URL = URL(string: "https://wol.jw.org")!) -> [WOLSearchResult] {
        var results: [WOLSearchResult] = []

        // Cada bloco começa em <ul class="directory resultContentTopic">.
        let blocks = blocksStartingWith("resultcontenttopic", in: html)
        for block in blocks {
            guard let captionAnchor = firstAnchor(
                in: block,
                requiringClass: "lnk"
            ) ?? firstAnchor(in: block, requiringClass: nil) else { continue }

            let title = HTMLTextExtractor.decodeEntities(captionAnchor.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let url = absoluteURL(captionAnchor.href, baseURL: baseURL) else { continue }

            let publication = firstListItemText(in: block, classedAs: "ref")
            let subResults = subResults(in: block, baseURL: baseURL)

            results.append(WOLSearchResult(
                title: title,
                url: url,
                publication: publication,
                subResults: subResults
            ))
        }
        return results
    }

    // MARK: - Varredura

    private struct AnchorReference {
        var href: String
        var text: String
        var classes: [String]
    }

    /// Blocos `<... class="…resultcontenttopic…">` … balanceados por nome de tag.
    private static func blocksStartingWith(_ className: String, in html: String) -> [String] {
        var blocks: [String] = []
        let characters = Array(html)
        var index = 0
        let needle = Array(className)
        let lowercased = Array(html.lowercased())

        while index < characters.count {
            guard let position = find(needle, from: index, in: lowercased) else { break }
            // Precisa estar dentro da tag de abertura.
            guard let open = lastTagOpen(before: position, in: characters),
                  let openEnd = firstIndex(of: ">", from: position, in: characters) else {
                index = position + needle.count
                continue
            }
            let tagName = tagName(at: open, in: characters)
            guard let close = matchingClosingTag(named: tagName, from: openEnd + 1, in: characters) else {
                index = position + needle.count
                continue
            }
            blocks.append(String(characters[open..<close]))
            index = close
        }
        return blocks
    }

    private static func lastTagOpen(before position: Int, in characters: [Character]) -> Int? {
        var index = position
        while index >= 0 {
            if characters[index] == "<" { return index }
            if characters[index] == ">" { return nil }
            index -= 1
        }
        return nil
    }

    private static func tagName(at open: Int, in characters: [Character]) -> String {
        var index = open + 1
        var name = ""
        while index < characters.count, !characters[index].isWhitespace, characters[index] != ">" {
            name.append(characters[index])
            index += 1
        }
        return name.lowercased()
    }

    private static func matchingClosingTag(named name: String, from start: Int, in characters: [Character]) -> Int? {
        guard !name.isEmpty else { return nil }
        let needle = Array("</\(name)")
        var depth = 1
        var index = max(0, start)
        let lowercased = characters.map { Character(String($0).lowercased()) }
        let openNeedle = Array("<\(name)")

        while index < characters.count {
            if find(needle, from: index, in: lowercased) == index {
                depth -= 1
                if depth == 0 { return index }
                index += needle.count
                continue
            }
            if find(openNeedle, from: index, in: lowercased) == index {
                // Verifica fronteira de nome (<ul> vs <ulx>).
                let after = index + openNeedle.count
                if after < characters.count {
                    let boundary = lowercased[after]
                    if boundary == ">" || boundary == " " || boundary == "\t" || boundary == "\n" || boundary == "/" {
                        depth += 1
                    }
                } else {
                    depth += 1
                }
                index += openNeedle.count
                continue
            }
            index += 1
        }
        return nil
    }

    private static func firstAnchor(in html: String, requiringClass className: String?) -> AnchorReference? {
        let anchors = allAnchors(in: html)
        guard let className else { return anchors.first }
        return anchors.first { $0.classes.contains(className.lowercased()) }
    }

    /// Todos os links `<a href="…">…</a>` na ordem em que aparecem.
    private static func allAnchors(in html: String) -> [AnchorReference] {
        var anchors: [AnchorReference] = []
        let characters = Array(html)
        let lowercased = Array(html.lowercased())
        let needle = Array("<a")
        var index = 0

        while index < characters.count {
            guard let position = find(needle, from: index, in: lowercased) else { break }
            let after = position + needle.count
            guard after < characters.count else { break }
            let boundary = lowercased[after]
            guard boundary == ">" || boundary == " " || boundary == "\t" || boundary == "\n" else {
                index = after
                continue
            }
            guard let openEnd = firstIndex(of: ">", from: position, in: characters),
                  let close = find(Array("</a"), from: openEnd + 1, in: lowercased) else { break }
            let tagText = String(characters[position..<openEnd])
            let text = HTMLTextExtractor.stripTags(String(characters[(openEnd + 1)..<close]))
            anchors.append(AnchorReference(
                href: attribute("href", in: tagText) ?? "",
                text: text,
                classes: (attribute("class", in: tagText) ?? "")
                    .split(separator: " ")
                    .map { $0.lowercased() }
            ))
            index = close + 3
        }
        return anchors
    }

    private static func firstListItemText(in html: String, classedAs className: String) -> String? {
        guard let listItem = firstElementBody(in: html, named: "li", classedAs: className) else { return nil }
        let text = HTMLTextExtractor.decodeEntities(HTMLTextExtractor.stripTags(listItem))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : collapse(text)
    }

    private static func firstElementBody(in html: String, named name: String, classedAs className: String) -> String? {
        let characters = Array(html)
        let lowercased = Array(html.lowercased())
        let needle = Array("<\(name)")
        var index = 0

        while index < characters.count {
            guard let position = find(needle, from: index, in: lowercased) else { return nil }
            let after = position + needle.count
            guard after < characters.count else { return nil }
            let boundary = lowercased[after]
            guard boundary == ">" || boundary == " " || boundary == "\t" || boundary == "\n" else {
                index = after
                continue
            }
            guard let openEnd = firstIndex(of: ">", from: position, in: characters) else { return nil }
            let tagText = String(characters[position..<openEnd])
            let classes = (attribute("class", in: tagText) ?? "")
                .split(separator: " ")
                .map { $0.lowercased() }
            if classes.contains(className.lowercased()),
               let close = matchingClosingTag(named: name, from: openEnd + 1, in: characters) {
                return String(characters[(openEnd + 1)..<close])
            }
            index = openEnd + 1
        }
        return nil
    }

    private static func subResults(in block: String, baseURL: URL) -> [WOLSearchSubResult] {
        guard let section = firstElementBody(in: block, named: "li", classedAs: "resultSubheadings") else {
            return []
        }
        var results: [WOLSearchSubResult] = []
        for anchor in allAnchors(in: section) {
            let title = HTMLTextExtractor.decodeEntities(anchor.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let url = absoluteURL(anchor.href, baseURL: baseURL) else { continue }
            results.append(WOLSearchSubResult(title: collapse(title), url: url))
        }
        return results
    }

    // MARK: - Utilitários

    private static func attribute(_ name: String, in tag: String) -> String? {
        let characters = Array(tag)
        let lowercased = Array(tag.lowercased())
        let needle = Array("\(name.lowercased())=")
        guard let position = find(needle, from: 0, in: lowercased) else { return nil }
        if position > 0 {
            let previous = lowercased[position - 1]
            guard previous.isWhitespace else { return nil }
        }
        var index = position + needle.count
        guard index < characters.count else { return nil }
        let quote = characters[index]
        if quote == "\"" || quote == "'" {
            index += 1
            var value = ""
            while index < characters.count, characters[index] != quote {
                value.append(characters[index])
                index += 1
            }
            return HTMLTextExtractor.decodeEntities(value)
        }
        var value = ""
        while index < characters.count, !characters[index].isWhitespace, characters[index] != ">" {
            value.append(characters[index])
            index += 1
        }
        return value.isEmpty ? nil : HTMLTextExtractor.decodeEntities(value)
    }

    private static func absoluteURL(_ href: String, baseURL: URL) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }
        if trimmed.hasPrefix("/") {
            return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func firstIndex(of character: Character, from start: Int, in characters: [Character]) -> Int? {
        var index = max(0, start)
        while index < characters.count {
            if characters[index] == character { return index }
            index += 1
        }
        return nil
    }

    private static func find(_ needle: [Character], from start: Int, in characters: [Character]) -> Int? {
        guard !needle.isEmpty else { return nil }
        var index = max(0, start)
        while index + needle.count <= characters.count {
            var matches = true
            for offset in 0..<needle.count where characters[index + offset] != needle[offset] {
                matches = false
                break
            }
            if matches { return index }
            index += 1
        }
        return nil
    }
}
