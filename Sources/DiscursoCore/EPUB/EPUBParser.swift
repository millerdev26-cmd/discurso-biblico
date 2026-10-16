//
//  EPUBParser.swift
//  DiscursoCore
//
//  Leitor de EPUB 2 e EPUB 3 construído sobre o leitor ZIP próprio.
//
//  Etapas:
//   1. `META-INF/container.xml` -> caminho do arquivo OPF;
//   2. OPF -> metadados, manifesto e ordem de leitura (spine);
//   3. navegação: documento `nav` (EPUB 3) ou `toc.ncx` (EPUB 2);
//      se não houver nenhum dos dois, o sumário é gerado a partir dos
//      títulos internos dos capítulos;
//   4. texto de cada capítulo extraído do XHTML, pronto para leitura,
//      pesquisa local e indexação.
//
//  Também detecta conteúdo protegido (`META-INF/encryption.xml` ou entradas
//  criptografadas no ZIP) e recusa a leitura, sem tentar contornar proteções.
//

import Foundation

public enum EPUBParser {

    /// Abre um EPUB a partir do conteúdo do arquivo.
    ///
    /// - Parameters:
    ///   - data: bytes do arquivo `.epub`.
    ///   - includeHTML: guarda o XHTML bruto de cada capítulo (necessário para
    ///     o leitor com formatação; desligado economiza memória).
    ///   - verifyChecksums: valida o CRC-32 das entradas (recomendado).
    public static func parse(
        data: Data,
        includeHTML: Bool = true,
        verifyChecksums: Bool = true
    ) throws -> EPUBBook {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(data: data)
        } catch {
            throw EPUBError.unreadable(reason: (error as? LocalizedError)?.errorDescription ?? "pacote inválido")
        }

        // Proteção de conteúdo
        switch protectionStatus(in: data) {
        case .protectedContent(let reason):
            throw EPUBError.protectedContent(reason)
        case .unprotected, .unknown:
            break
        }

        var diagnostics = EPUBDiagnostics()

        // 1. container.xml
        let containerPath = "META-INF/container.xml"
        var containerXML = try? archive.string(forName: containerPath, verifyChecksum: verifyChecksums)
        if containerXML == nil, let entry = archive.firstMatchingXML(named: "container.xml") {
            containerXML = try? archive.string(for: entry, verifyChecksum: verifyChecksums)
        }
        guard let containerXML, !containerXML.isEmpty else {
            throw EPUBError.missingContainer
        }

        guard let packagePath = firstAttributeValue(
            in: containerXML,
            elementName: "rootfile",
            attributeName: "full-path"
        ) ?? firstAttributeValue(in: containerXML, elementName: "rootfile", attributeName: "fullpath") else {
            throw EPUBError.missingContainer
        }
        let normalizedPackagePath = EPUPPath.normalize(packagePath)

        var opfXML = try? archive.string(forName: normalizedPackagePath, verifyChecksum: verifyChecksums)
        if let opfXMLValue = opfXML, !opfXMLValue.isEmpty {
            opfXML = opfXMLValue
        } else if let entry = archive.firstMatchingXML(withSuffix: ".opf") {
            opfXML = try? archive.string(for: entry, verifyChecksum: verifyChecksums)
        }
        guard let opfXML, !opfXML.isEmpty else {
            throw EPUBError.missingPackage(normalizedPackagePath)
        }

        let packageDirectory = EPUPPath.directory(of: normalizedPackagePath)

        // 2. OPF
        var metadata = parseMetadata(from: opfXML)
        metadata.packageVersion = firstAttributeValue(in: opfXML, elementName: "package", attributeName: "version")
        if metadata.packageVersion == nil {
            metadata.packageVersion = firstAttributeValue(in: opfXML, elementName: "package", attributeName: "version")
        }
        let manifest = parseManifest(from: opfXML, packageDirectory: packageDirectory)
        let spine = parseSpine(from: opfXML, manifest: manifest)

        guard !spine.isEmpty else { throw EPUBError.emptySpine }

        // 3. Navegação
        let navigationDocument = manifest.first { $0.isNavigationDocument }
        var navigation: [EPUBNavigationEntry] = []
        if let navigationDocument,
           let html = try? archive.string(forName: navigationDocument.fullPath, verifyChecksum: verifyChecksums) {
            diagnostics.hasNavigationDocument = true
            navigation = parseNavigationDocument(
                html: html,
                baseDirectory: EPUPPath.directory(of: navigationDocument.fullPath)
            )
        }
        if navigation.isEmpty,
           let ncxPath = parseNCXPath(from: opfXML, packageDirectory: packageDirectory)
            ?? archive.firstMatchingXML(withSuffix: ".ncx")?.name {
            if let ncx = try? archive.string(forName: ncxPath, verifyChecksum: verifyChecksums) {
                diagnostics.usedNCXFallback = true
                let base = EPUPPath.directory(of: ncxPath)
                navigation = parseNCX(html: ncx, baseDirectory: base)
            }
        }

        // 4. Capítulos
        var chapters: [EPUBChapter] = []
        for (index, item) in spine.enumerated() {
            guard let entry = archive.entry(named: item.fullPath) else {
                diagnostics.missingResources.append(item.fullPath)
                continue
            }
            guard let rawHTML = try? archive.string(for: entry, verifyChecksum: verifyChecksums) else {
                diagnostics.missingResources.append(item.fullPath)
                continue
            }
            let extraction = HTMLTextExtractor.extract(from: rawHTML)
            let title = extraction.headings.first?.text
                ?? extraction.title
                ?? fallbackTitle(for: item, index: index)
            chapters.append(EPUBChapter(
                id: item.id,
                index: index,
                title: title,
                fullPath: item.fullPath,
                html: includeHTML ? rawHTML : nil,
                text: extraction.text,
                headings: extraction.headings
            ))
        }

        guard !chapters.isEmpty else { throw EPUBError.unreadable(reason: "nenhum capítulo pôde ser lido") }

        // Resolve índices de capítulo no sumário (por caminho).
        var chapterIndexByPath: [String: Int] = [:]
        for chapter in chapters {
            chapterIndexByPath[EPUPPath.normalize(chapter.fullPath)] = chapter.index
        }
        navigation = navigation.map { entry in
            var updated = entry
            updated.chapterIndex = chapterIndexByPath[EPUPPath.normalize(entry.fullPath)]
            return updated
        }

        if navigation.isEmpty {
            diagnostics.generatedNavigationFromHeadings = true
            navigation = generateNavigation(from: chapters)
        }

        // Capa
        var coverImagePath: String?
        if let cover = manifest.first(where: { $0.isCoverImage }) {
            coverImagePath = cover.fullPath
        } else if let coverReference = firstAttributeValue(in: opfXML, elementName: "meta", attributeName: "content"),
                  let coverItem = manifest.first(where: { $0.id == coverReference }) {
            coverImagePath = coverItem.fullPath
        }

        var finalMetadata = metadata
        if finalMetadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalMetadata.title = chapters.first?.title ?? "Material importado"
        }

        return EPUBBook(
            metadata: finalMetadata,
            manifest: manifest,
            chapters: chapters,
            navigation: navigation,
            coverImagePath: coverImagePath,
            packagePath: normalizedPackagePath,
            diagnostics: diagnostics
        )
    }

    /// Abre um EPUB a partir de um arquivo no disco.
    public static func parse(
        contentsOf url: URL,
        includeHTML: Bool = true,
        verifyChecksums: Bool = true
    ) throws -> EPUBBook {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw EPUBError.unreadable(reason: error.localizedDescription)
        }
        return try parse(data: data, includeHTML: includeHTML, verifyChecksums: verifyChecksums)
    }

    // MARK: - Proteção de conteúdo

    /// Situação de proteção declarada por um pacote EPUB.
    ///
    /// A verificação olha apenas para o que o próprio pacote declara
    /// (`META-INF/encryption.xml` e entradas criptografadas). Nenhuma proteção
    /// é removida ou contornada.
    public enum ProtectionStatus: Equatable, Sendable {
        /// Sem indícios de proteção.
        case unprotected
        /// Conteúdo (não apenas fontes) declarado como criptografado.
        case protectedContent(String)
        /// O pacote não pôde ser inspecionado.
        case unknown
    }

    /// Verifica se um arquivo EPUB declara proteção de conteúdo.
    public static func protectionStatus(in data: Data) -> ProtectionStatus {
        guard let archive = try? ZipArchive(data: data) else { return .unknown }

        if let encryption = try? archive.data(forName: "META-INF/encryption.xml", verifyChecksum: false),
           !encryption.isEmpty {
            // O arquivo de criptografia também é usado para fontes obfuscadas.
            let xml = String(data: encryption, encoding: .utf8) ?? ""
            let encryptsContent = xml.contains("EncryptedData") && (xml.contains("EncryptedKey") || xml.contains("EncryptionMethod"))
            let obfuscatesOnlyFonts = !xml.contains("application/xhtml") && xml.contains("font")
            if encryptsContent, !obfuscatesOnlyFonts {
                return .protectedContent("mecanismo de criptografia declarado no pacote")
            }
        }
        if let encryptedEntry = archive.entries.first(where: { $0.isEncrypted && !$0.isDirectory }) {
            return .protectedContent("item \(encryptedEntry.name) com criptografia")
        }
        return .unprotected
    }

    // MARK: - OPF

    private static func parseMetadata(from opf: String) -> EPUBMetadata {
        var metadata = EPUBMetadata()
        metadata.title = firstElementText(in: opf, elementName: "title") ?? ""
        metadata.creators = allElementTexts(in: opf, elementName: "creator")
        metadata.language = firstElementText(in: opf, elementName: "language")
        metadata.identifier = firstElementText(in: opf, elementName: "identifier")
        metadata.publisher = firstElementText(in: opf, elementName: "publisher")
        metadata.publishedDate = firstElementText(in: opf, elementName: "date")
        metadata.bookDescription = firstElementText(in: opf, elementName: "description")
        metadata.rights = firstElementText(in: opf, elementName: "rights")
        return metadata
    }

    private static func parseManifest(from opf: String, packageDirectory: String) -> [EPUBManifestItem] {
        var items: [EPUBManifestItem] = []
        for tag in allTagTexts(in: opf, elementName: "item") {
            guard let id = attributeValue(inTag: tag, attributeName: "id"),
                  let href = attributeValue(inTag: tag, attributeName: "href")
            else { continue }
            let mediaType = attributeValue(inTag: tag, attributeName: "media-type") ?? ""
            let properties = (attributeValue(inTag: tag, attributeName: "properties") ?? "")
                .split(separator: " ")
                .map(String.init)
            let fullPath = EPUPPath.resolve(relativeTo: packageDirectory, path: href)
            items.append(EPUBManifestItem(
                id: id,
                href: href,
                mediaType: mediaType,
                properties: properties,
                fullPath: fullPath
            ))
        }
        return items
    }

    private static func parseSpine(from opf: String, manifest: [EPUBManifestItem]) -> [EPUBManifestItem] {
        let manifestByID: [String: EPUBManifestItem] = Dictionary(
            uniqueKeysWithValues: manifest.map { ($0.id, $0) }
        )
        var spineItems: [EPUBManifestItem] = []
        for tag in allTagTexts(in: opf, elementName: "itemref") {
            guard let idReference = attributeValue(inTag: tag, attributeName: "idref") else { continue }
            if attributeValue(inTag: tag, attributeName: "linear")?.lowercased() == "no" {
                // Itens não lineares (capas, extras) ficam fora da ordem de leitura.
                continue
            }
            guard let item = manifestByID[idReference], item.isXHTML else { continue }
            spineItems.append(item)
        }
        if spineItems.isEmpty {
            // Alguns arquivos não marcam "linear"; tenta novamente sem o filtro.
            for tag in allTagTexts(in: opf, elementName: "itemref") {
                guard let idReference = attributeValue(inTag: tag, attributeName: "idref"),
                      let item = manifestByID[idReference], item.isXHTML
                else { continue }
                spineItems.append(item)
            }
        }
        return spineItems
    }

    private static func parseNCXPath(from opf: String, packageDirectory: String) -> String? {
        // Referência pelo atributo `toc` do elemento `spine`.
        if let spineTag = allTagTexts(in: opf, elementName: "spine").first,
           let tocID = attributeValue(inTag: spineTag, attributeName: "toc"),
           let item = parseManifest(from: opf, packageDirectory: packageDirectory).first(where: { $0.id == tocID }) {
            return item.fullPath
        }
        return nil
    }

    // MARK: - Navegação

    static func parseNavigationDocument(html: String, baseDirectory: String) -> [EPUBNavigationEntry] {
        // Usa o primeiro <nav> marcado como sumário; se não houver marcação,
        // usa o primeiro <nav> do documento; se não houver <nav>, percorre o
        // documento inteiro procurando listas com links.
        //
        // O corpo é usado com a marcação preservada (precisamos dos <a href>),
        // mas a decisão de qual <nav> é o sumário olha para a tag de abertura,
        // onde fica `epub:type="toc"` / `role="doc-toc"`.
        let navBlocks = elementBlocks(in: html, elementName: "nav")
        let candidate = navBlocks.first { block in
            let lower = block.openingTag.lowercased()
            return lower.contains("type=\"toc\"")
                || lower.contains("type='toc'")
                || lower.contains("role=\"doc-toc\"")
                || lower.contains("role='doc-toc'")
        } ?? navBlocks.first

        return parseOrderedListNavigation(
            in: candidate?.body ?? html,
            baseDirectory: baseDirectory,
            level: 0
        )
    }

    /// Percorre `<ol><li><a href>` aninhados, atribuindo nível pela profundidade.
    private static func parseOrderedListNavigation(
        in html: String,
        baseDirectory: String,
        level: Int
    ) -> [EPUBNavigationEntry] {
        var entries: [EPUBNavigationEntry] = []
        let characters = Array(html)
        var listDepth = 0
        var index = 0
        var pendingListOpen = false

        while index < characters.count {
            guard characters[index] == "<" else {
                index += 1
                continue
            }
            guard let close = characters[index...].firstIndex(of: ">") else { break }
            let tag = String(characters[(index + 1)..<close]).trimmingCharacters(in: .whitespaces)
            let lowercased = tag.lowercased()
            let isClosing = lowercased.hasPrefix("/")

            if lowercased.hasPrefix("ol") || lowercased.hasPrefix("ul") {
                if isClosing {
                    listDepth = max(0, listDepth - 1)
                } else {
                    pendingListOpen = true
                }
                index = close + 1
                continue
            }

            if lowercased.hasPrefix("a ") || lowercased == "a" || lowercased.hasPrefix("a\t") {
                if !isClosing,
                   let href = attributeValue(inTag: tag, attributeName: "href") {
                    if pendingListOpen {
                        listDepth += 1
                        pendingListOpen = false
                    }
                    // Texto do link até </a>
                    let textStart = close + 1
                    var textEnd = textStart
                    while textEnd < characters.count {
                        if characters[textEnd] == "<" {
                            let remainder = String(characters[textEnd...].prefix(5)).lowercased()
                            if remainder.hasPrefix("</a") { break }
                        }
                        textEnd += 1
                    }
                    let label = HTMLTextExtractor.decodeEntities(
                        String(characters[textStart..<min(textEnd, characters.count)])
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    let (path, fragment) = EPUPPath.splitFragment(href)
                    let fullPath = EPUPPath.resolve(relativeTo: baseDirectory, path: path)
                    if !label.isEmpty {
                        entries.append(EPUBNavigationEntry(
                            title: collapse(label),
                            fullPath: fullPath,
                            fragment: fragment,
                            level: max(0, listDepth - 1)
                        ))
                    }
                }
                index = close + 1
                continue
            }

            index = close + 1
        }

        if entries.isEmpty, level == 0 {
            return []
        }
        return entries
    }

    /// Sumário do EPUB 2 (`toc.ncx`).
    ///
    /// Varre as tags em ordem. O rótulo vem de `<navLabel><text>` e a emissão
    /// acontece no `<content src="…">` seguinte; `navPoint` aninhados só
    /// aumentam a profundidade, de modo que cada entrada sai com o nível certo.
    static func parseNCX(html: String, baseDirectory: String) -> [EPUBNavigationEntry] {
        var entries: [EPUBNavigationEntry] = []
        let characters = Array(html)
        var depth = 0
        var pendingLabel: String?

        scanTags(in: characters, from: 0) { tag in
            switch tag.name {
            case "navpoint":
                if tag.isClosing {
                    depth = max(0, depth - 1)
                } else if !tag.isSelfClosing {
                    depth += 1
                    // O rótulo sempre vem antes do destino dentro do mesmo
                    // navPoint; limpar aqui evita reaproveitar texto anterior.
                    pendingLabel = nil
                }
            case "text":
                guard !tag.isClosing, !tag.isSelfClosing,
                      let close = findClosingTag(named: "text", from: tag.end + 1, in: characters)
                else { return }
                let raw = String(characters[(tag.end + 1)..<close])
                pendingLabel = collapse(HTMLTextExtractor.decodeEntities(HTMLTextExtractor.stripTags(raw)))
            case "content":
                guard !tag.isClosing, depth > 0,
                      let label = pendingLabel, !label.isEmpty,
                      let source = attributeValue(inTag: tag.fullText, attributeName: "src")
                else { return }
                let (path, fragment) = EPUPPath.splitFragment(source)
                let fullPath = EPUPPath.resolve(relativeTo: baseDirectory, path: path)
                entries.append(EPUBNavigationEntry(
                    title: label,
                    fullPath: fullPath,
                    fragment: fragment,
                    level: max(0, depth - 1)
                ))
                pendingLabel = nil
            default:
                break
            }
        }
        return entries
    }

    /// Gera um sumário a partir dos títulos internos quando o EPUB não traz um.
    private static func generateNavigation(from chapters: [EPUBChapter]) -> [EPUBNavigationEntry] {
        var entries: [EPUBNavigationEntry] = []
        for chapter in chapters {
            if chapter.headings.isEmpty {
                entries.append(EPUBNavigationEntry(
                    title: chapter.title,
                    fullPath: chapter.fullPath,
                    level: 0,
                    chapterIndex: chapter.index
                ))
                continue
            }
            for heading in chapter.headings where heading.level <= 2 {
                entries.append(EPUBNavigationEntry(
                    title: heading.text,
                    fullPath: chapter.fullPath,
                    level: max(0, heading.level - 1),
                    chapterIndex: chapter.index
                ))
            }
        }
        return entries
    }

    // MARK: - Utilitários de XML

    /// Texto do primeiro elemento com o nome informado.
    static func firstElementText(in xml: String, elementName: String) -> String? {
        allElementTexts(in: xml, elementName: elementName).first
    }

    /// Texto de todos os elementos com o nome informado (sem aninhamento).
    /// O nome é comparado pelo nome local, então `<dc:title>` casa com "title".
    static func allElementTexts(in xml: String, elementName: String) -> [String] {
        elementBlocks(in: xml, elementName: elementName).map { block in
            HTMLTextExtractor.decodeEntities(HTMLTextExtractor.stripTags(block.body))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    /// Tag de abertura e corpo bruto dos elementos com o nome local informado.
    ///
    /// O corpo preserva a marcação interna (necessário para o documento de
    /// navegação) e o aninhamento do mesmo elemento é respeitado.
    static func elementBlocks(in xml: String, elementName: String) -> [(openingTag: String, body: String)] {
        let characters = Array(xml)
        let target = elementName.lowercased()
        var blocks: [(openingTag: String, body: String)] = []
        var openingTag: String?
        var bodyStart = 0
        var depth = 0

        scanTags(in: characters, from: 0) { tag in
            guard tag.name == target else { return }
            if tag.isClosing {
                guard depth > 0 else { return }
                depth -= 1
                if depth == 0, let opening = openingTag {
                    blocks.append((opening, String(characters[bodyStart..<tag.start])))
                    openingTag = nil
                }
                return
            }
            if openingTag == nil {
                guard !tag.isSelfClosing else { return }
                openingTag = tag.fullText
                bodyStart = tag.end + 1
                depth = 1
            } else if !tag.isSelfClosing {
                depth += 1
            }
        }
        return blocks
    }

    /// Tags brutas (`<item .../>`) com o nome local informado, sem as de fechamento.
    static func allTagTexts(in xml: String, elementName: String) -> [String] {
        let characters = Array(xml)
        let target = elementName.lowercased()
        var results: [String] = []
        scanTags(in: characters, from: 0) { tag in
            if tag.name == target, !tag.isClosing {
                results.append(tag.fullText)
            }
        }
        return results
    }

    // MARK: - Varredura de XML

    /// Tag encontrada durante a varredura de um documento XML/HTML.
    struct ScannedTag {
        /// Nome local em minúsculas, sem prefixo de namespace ("dc:title" -> "title").
        var name: String
        /// Conteúdo bruto entre "<" e ">".
        var raw: String
        var isClosing: Bool
        var isSelfClosing: Bool
        /// Índice do "<" da tag.
        var start: Int
        /// Índice do ">" da tag.
        var end: Int

        /// Tag reconstruída, incluindo os sinais de menor e maior.
        var fullText: String { "<\(raw)>" }
    }

    /// Varre as tags do documento em ordem. Comentários, CDATA e declarações
    /// são pulados sem gerar tag.
    static func scanTags(in characters: [Character], from start: Int, body: (ScannedTag) -> Void) {
        var index = max(0, start)
        while index < characters.count {
            guard let open = characters[index...].firstIndex(of: "<") else { return }
            let cursor = open + 1
            guard cursor < characters.count else { return }

            switch characters[cursor] {
            case "!":
                if characters[cursor...].starts(with: Array("!--")) {
                    if let end = find(Array("-->"), from: cursor + 1, in: characters) {
                        index = end + 3
                        continue
                    }
                    return
                }
                if characters[cursor...].starts(with: Array("![CDATA[")) {
                    if let end = find(Array("]]>"), from: cursor + 1, in: characters) {
                        index = end + 3
                        continue
                    }
                    return
                }
                // Declaração (<!DOCTYPE ...>)
                if let end = characters[cursor...].firstIndex(of: ">") {
                    index = end + 1
                    continue
                }
                return
            case "?":
                if let end = characters[cursor...].firstIndex(of: ">") {
                    index = end + 1
                    continue
                }
                return
            default:
                break
            }

            guard let end = findTagEnd(from: cursor, in: characters) else { return }
            let raw = String(characters[cursor..<end])
            var content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            var isClosing = false
            if content.hasPrefix("/") {
                isClosing = true
                content.removeFirst()
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let isSelfClosing = content.hasSuffix("/")
            if isSelfClosing { content.removeLast() }
            let namePart = content.prefix { !$0.isWhitespace }
            let name = localName(of: String(namePart))
            if !name.isEmpty {
                body(ScannedTag(
                    name: name,
                    raw: raw,
                    isClosing: isClosing,
                    isSelfClosing: isSelfClosing,
                    start: open,
                    end: end
                ))
            }
            index = end + 1
        }
    }

    /// Nome local de uma tag: remove o prefixo de namespace ("dc:title" -> "title").
    static func localName(of rawName: String) -> String {
        let lower = rawName.lowercased()
        guard let colon = lower.lastIndex(of: ":") else { return lower }
        return String(lower[lower.index(after: colon)...])
    }

    /// Fim de uma tag, respeitando aspas em atributos.
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

    static func attributeValue(inTag tag: String, attributeName: String) -> String? {
        // Trabalha em arrays de caracteres para não depender de índices de
        // strings em minúsculas (o `lowercased()` pode mudar o comprimento).
        let characters = Array(tag)
        let lowercased = Array(tag.lowercased())
        let needle = Array(attributeName.lowercased() + "=")
        guard let position = find(needle, from: 0, in: lowercased) else { return nil }

        // Garante que o atributo comece em uma fronteira (espaço ou início).
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
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var value = ""
        while index < characters.count, !characters[index].isWhitespace, characters[index] != ">" , characters[index] != "/" {
            value.append(characters[index])
            index += 1
        }
        return HTMLTextExtractor.decodeEntities(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Valor do primeiro atributo encontrado em qualquer tag com o nome dado.
    static func firstAttributeValue(in xml: String, elementName: String, attributeName: String) -> String? {
        for tag in allTagTexts(in: xml, elementName: elementName) {
            if let value = attributeValue(inTag: tag, attributeName: attributeName) {
                return value
            }
        }
        return nil
    }

    static func findClosingTag(named name: String, from start: Int, in characters: [Character]) -> Int? {
        let needle = Array("</\(name.lowercased())")
        let lowercased = characters.map { Character(String($0).lowercased()) }
        return find(needle, from: start, in: lowercased)
    }

    static func find(_ needle: [Character], from start: Int, in characters: [Character]) -> Int? {
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

    private static func collapse(_ text: String) -> String {
        var result = ""
        var lastWasSpace = false
        for character in text {
            if character.isWhitespace {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fallbackTitle(for item: EPUBManifestItem, index: Int) -> String {
        let name = item.fullPath.split(separator: "/").last.map(String.init) ?? item.href
        let withoutExtension = name.split(separator: ".").first.map(String.init) ?? name
        let cleaned = withoutExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Capítulo \(index + 1)" : trimmed
    }
}

private extension ZipArchive {
    /// Primeira entrada XML cujo nome termina com o sufixo informado.
    func firstMatchingXML(named name: String) -> ZipEntry? {
        entries.first { $0.name.lowercased().hasSuffix(name.lowercased()) }
    }

    /// Primeira entrada XML com o sufixo informado.
    func firstMatchingXML(withSuffix suffix: String) -> ZipEntry? {
        entries.first { $0.name.lowercased().hasSuffix(suffix.lowercased()) }
    }
}
