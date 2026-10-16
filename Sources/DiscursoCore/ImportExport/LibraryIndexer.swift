//
//  LibraryIndexer.swift
//  DiscursoCore
//
//  Indexação do conteúdo dos materiais importados.
//
//  A indexação transforma o arquivo em "pedaços" pesquisáveis com o
//  localizador necessário para reabrir o material no ponto exato:
//
//     EPUB  -> um pedaço por capítulo (e subdivisões de capítulos longos);
//     PDF   -> um pedaço por página;
//     TXT / Markdown / HTML -> um pedaço por parágrafo agrupado.
//
//  Tudo funciona offline e sem depender da rede.
//
//  A extração de PDF tem duas implementações:
//   - `PDFKitTextExtracting` (camada iOS, no app): correta para qualquer PDF;
//   - `PDFTextExtractor` (este pacote): mínima, usada nos testes e como
//     último recurso — ver as limitações documentadas nesse arquivo.
//

import Foundation

/// Resultado da indexação de um material.
public struct LibraryIndexingResult: Sendable {
    public var index: LibraryTextIndex
    /// Título sugerido pelas informações internas do arquivo (metadados).
    public var suggestedTitle: String?
    public var author: String?
    /// Capítulos (EPUB) ou páginas (PDF) extraídos.
    public var unitCount: Int?
    public var warnings: [String]

    public init(
        index: LibraryTextIndex,
        suggestedTitle: String? = nil,
        author: String? = nil,
        unitCount: Int? = nil,
        warnings: [String] = []
    ) {
        self.index = index
        self.suggestedTitle = suggestedTitle
        self.author = author
        self.unitCount = unitCount
        self.warnings = warnings
    }
}

/// Erros de indexação.
public enum LibraryIndexingError: LocalizedError, Equatable {
    case unsupportedKind(String)
    case noTextFound
    case corrupted(reason: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedKind(let kind):
            return "A indexação de \(kind) ainda não está disponível."
        case .noTextFound:
            return "Nenhum texto pôde ser extraído do arquivo."
        case .corrupted(let reason):
            return "O arquivo parece estar corrompido: \(reason)."
        }
    }
}

public enum LibraryIndexer {

    /// Constrói o índice de um material a partir de seus bytes.
    ///
    /// - Parameters:
    ///   - item: material (fornece tipo, extensão e identificador).
    ///   - data: conteúdo do arquivo.
    ///   - pdfTextExtracting: implementação de extração de PDF (o app iOS usa
    ///     PDFKit; o padrão é o extrator mínimo deste pacote).
    public static func buildIndex(
        for item: LibraryItem,
        data: Data,
        pdfTextExtracting: PDFTextExtracting? = nil
    ) throws -> LibraryIndexingResult {
        try buildIndex(
            itemID: item.id,
            kind: item.kind,
            fileExtension: item.fileExtension,
            data: data,
            pdfTextExtracting: pdfTextExtracting
        )
    }

    /// Variante usada pelos testes e por importações recém-preparadas.
    public static func buildIndex(
        itemID: UUID,
        kind: LibraryItemKind,
        fileExtension: String,
        data: Data,
        pdfTextExtracting: PDFTextExtracting? = nil
    ) throws -> LibraryIndexingResult {
        switch kind {
        case .plainText:
            return try indexPlainText(itemID: itemID, data: data)
        case .markdown:
            return try indexMarkdown(itemID: itemID, data: data)
        case .html:
            return try indexHTML(itemID: itemID, data: data)
        case .epub:
            return try indexEPUB(itemID: itemID, data: data)
        case .pdf:
            return try indexPDF(itemID: itemID, data: data, extractor: pdfTextExtracting ?? PDFKitUnavailableExtractor())
        case .unsupported:
            throw LibraryIndexingError.unsupportedKind(
                fileExtension.uppercased().isEmpty ? "arquivos neste formato" : fileExtension.uppercased()
            )
        }
    }

    // MARK: - Texto, Markdown e HTML

    private static func indexPlainText(itemID: UUID, data: Data) throws -> LibraryIndexingResult {
        guard let text = TextFileDecoder.decode(data) else {
            throw LibraryIndexingError.corrupted(reason: "o texto não pôde ser decodificado")
        }
        let normalized = normalizeLineEndings(text)
        let units = splitIntoSections(normalized)
        let index = LibraryTextIndexBuilder.build(itemID: itemID, units: units)
        guard index.totalWordCount > 0 else { throw LibraryIndexingError.noTextFound }
        return LibraryIndexingResult(index: index, unitCount: units.count)
    }

    private static func indexMarkdown(itemID: UUID, data: Data) throws -> LibraryIndexingResult {
        guard let text = TextFileDecoder.decode(data) else {
            throw LibraryIndexingError.corrupted(reason: "o texto não pôde ser decodificado")
        }
        let plain = MarkdownPlainText.convert(normalizeLineEndings(text))
        let units = splitIntoSections(plain)
        let index = LibraryTextIndexBuilder.build(itemID: itemID, units: units)
        guard index.totalWordCount > 0 else { throw LibraryIndexingError.noTextFound }
        return LibraryIndexingResult(index: index, unitCount: units.count)
    }

    private static func indexHTML(itemID: UUID, data: Data) throws -> LibraryIndexingResult {
        guard let text = TextFileDecoder.decode(data) else {
            throw LibraryIndexingError.corrupted(reason: "o HTML não pôde ser decodificado")
        }
        let extraction = HTMLTextExtractor.extract(from: text, includeTitle: true)
        let units: [(title: String?, text: String)] = [(title: extraction.title, text: extraction.text)]
        let index = LibraryTextIndexBuilder.build(itemID: itemID, units: units)
        guard index.totalWordCount > 0 else { throw LibraryIndexingError.noTextFound }
        return LibraryIndexingResult(index: index, suggestedTitle: extraction.title, unitCount: 1)
    }

    // MARK: - EPUB

    private static func indexEPUB(itemID: UUID, data: Data) throws -> LibraryIndexingResult {
        let book: EPUBBook
        do {
            book = try EPUBParser.parse(data: data, includeHTML: false)
        } catch let error as EPUBError {
            throw LibraryIndexingError.corrupted(reason: error.errorDescription ?? "EPUB inválido")
        } catch {
            throw LibraryIndexingError.corrupted(reason: error.localizedDescription)
        }

        let units: [(title: String?, text: String)] = book.chapters.map { chapter in
            (title: chapter.title, text: chapter.text)
        }
        let index = LibraryTextIndexBuilder.build(itemID: itemID, units: units)
        guard index.totalWordCount > 0 else { throw LibraryIndexingError.noTextFound }

        var warnings: [String] = []
        if !book.diagnostics.missingResources.isEmpty {
            warnings.append("Alguns recursos do EPUB não foram encontrados (\(book.diagnostics.missingResources.count)).")
        }
        if book.diagnostics.usedNCXFallback {
            warnings.append("O sumário foi lido do formato antigo (toc.ncx).")
        }
        if book.diagnostics.generatedNavigationFromHeadings {
            warnings.append("O EPUB não traz sumário; os títulos internos foram usados para navegação.")
        }

        return LibraryIndexingResult(
            index: index,
            suggestedTitle: book.metadata.title.isEmpty ? nil : book.metadata.title,
            author: book.metadata.authorDescription,
            unitCount: book.chapters.count,
            warnings: warnings
        )
    }

    // MARK: - PDF

    private static func indexPDF(
        itemID: UUID,
        data: Data,
        extractor: PDFTextExtracting
    ) throws -> LibraryIndexingResult {
        let extraction = extractor.extractText(from: data)
        guard !extraction.isEncrypted else {
            throw LibraryIndexingError.corrupted(reason: "o PDF é protegido")
        }
        let units: [(title: String?, text: String)] = extraction.pages.enumerated().map { index, text in
            (title: "Página \(index + 1)", text: text)
        }
        let index = LibraryTextIndexBuilder.build(itemID: itemID, units: units)
        guard index.totalWordCount > 0 else { throw LibraryIndexingError.noTextFound }
        return LibraryIndexingResult(
            index: index,
            unitCount: extraction.pages.count,
            warnings: extraction.warnings
        )
    }

    // MARK: - Utilitários

    /// Divide um texto corrido em unidades por título de seção simples
    /// (linhas em MAIÚSCULAS curtas ou numeradas) — mantém o índice navegável.
    private static func splitIntoSections(_ text: String) -> [(title: String?, text: String)] {
        let lines = text.components(separatedBy: "\n")
        var units: [(title: String?, text: String)] = []
        var currentTitle: String?
        var buffer: [String] = []

        func flush() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                units.append((title: currentTitle, text: joined))
            }
            buffer = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isSectionHeading(trimmed) {
                flush()
                currentTitle = trimmed
            } else {
                buffer.append(line)
            }
        }
        flush()

        if units.isEmpty {
            let joined = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? [] : [(title: nil, text: joined)]
        }
        return units
    }

    private static func isSectionHeading(_ line: String) -> Bool {
        guard !line.isEmpty, line.count <= 60 else { return false }
        // "1. Título", "TÍTULO EM MAIÚSCULAS"
        if line.range(of: #"^\d{1,2}[.)]\s+\S"#, options: .regularExpression) != nil {
            return true
        }
        let letters = line.filter(\.isLetter)
        guard letters.count >= 3 else { return false }
        let uppercased = line.filter { $0.isUppercase }.count
        return uppercased >= letters.count && letters.count >= line.count / 2
    }

    private static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - Extração de PDF

/// Implementação de extração de texto de PDF.
///
/// No aplicativo iOS, use a implementação baseada em PDFKit
/// (`PDFKitTextExtracting`), que lida com fontes, páginas e codificações.
public protocol PDFTextExtracting: Sendable {
    func extractText(from data: Data) -> PDFExtraction
}

/// Extrator mínimo deste pacote (sem PDFKit), usado em testes e fallback.
public struct PDFKitUnavailableExtractor: PDFTextExtracting {
    public init() {}
    public func extractText(from data: Data) -> PDFExtraction {
        PDFTextExtractor.extract(data: data)
    }
}

// MARK: - Markdown

/// Conversão mínima de Markdown em texto simples, usada na indexação.
public enum MarkdownPlainText {

    /// Remove a marcação mais comum, preservando o texto:
    /// títulos (`#`), ênfase (`*`, `_`), links (`[texto](url)`), código (`),
    /// listas (`-`, `*`, números), citações (`>`) e cercas de código.
    public static func convert(_ markdown: String) -> String {
        var output: [String] = []
        var insideCodeFence = false

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideCodeFence.toggle()
                continue
            }
            if insideCodeFence {
                output.append(line)
                continue
            }

            var content = line
            // Citação no início da linha (pode ser aninhada: "> > texto").
            while content.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                content = String(content.trimmingCharacters(in: .whitespaces).dropFirst())
            }
            // Cabeçalhos
            while content.hasPrefix("#") { content.removeFirst() }
            content = content.trimmingCharacters(in: .whitespaces)
            // Marcadores de lista
            if let range = content.range(of: #"^([-*+]|\d{1,3}[.)])\s+"#, options: .regularExpression) {
                content.removeSubrange(range)
            }
            content = stripInline(content)
            output.append(content)
        }

        return output.joined(separator: "\n")
    }

    private static func stripInline(_ text: String) -> String {
        var result = text
        // Imagens: ![alt](url) -> alt
        result = result.replacingOccurrences(
            of: #"!\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Links: [texto](url) -> texto (url)
        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "$1 ($2)",
            options: .regularExpression
        )
        // Código em linha
        result = result.replacingOccurrences(of: "`", with: "")
        // Ênfase forte e simples (**a**, __a__, *a*, _a_)
        result = result.replacingOccurrences(
            of: #"(\*\*|__)(.+?)\1"#,
            with: "$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(\*|_)(.+?)\1"#,
            with: "$2",
            options: .regularExpression
        )
        // Linhas horizontais
        if result.trimmingCharacters(in: .whitespaces).range(
            of: #"^([-*_]\s*){3,}$"#,
            options: .regularExpression
        ) != nil {
            return ""
        }
        return result
    }
}
