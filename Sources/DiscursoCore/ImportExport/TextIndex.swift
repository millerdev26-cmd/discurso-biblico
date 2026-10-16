//
//  TextIndex.swift
//  DiscursoCore
//
//  Indexação e busca local no conteúdo dos materiais importados.
//
//  O índice é gravado em disco junto com o material (`library/indexes/<id>.json`)
//  e funciona 100% offline. Cada material é dividido em "pedaços" (capítulos
//  de EPUB, páginas de PDF, blocos de texto), e cada pedaço guarda o localizador
//  necessário para reabrir o material exatamente no ponto encontrado.
//
//  A busca é:
//   1. sem acentos e sem diferença de maiúsculas/minúsculas;
//   2. por expressão (frase) quando o usuário escreve várias palavras;
//   3. combinada com o título do material (documentos cujo título casa
//      aparecem primeiro, mesmo antes de abrir o conteúdo).
//

import Foundation

/// Um pedaço indexado de um material.
public struct LibraryTextChunk: Codable, Hashable, Sendable {
    /// Localizador para reabrir o material no ponto exato.
    public var locator: ReadingLocator
    /// Título do capítulo/página, quando houver.
    public var title: String?
    /// Texto original.
    public var text: String
    /// Texto normalizado (minúsculo, sem acentos) usado na busca.
    public var normalizedText: String
    /// Número de palavras (para ordenar e para o cálculo de duração).
    public var wordCount: Int

    public init(locator: ReadingLocator, title: String? = nil, text: String, normalizedText: String? = nil, wordCount: Int? = nil) {
        self.locator = locator
        self.title = title
        self.text = text
        self.normalizedText = normalizedText ?? PortugueseText.normalizedForSearch(text)
        self.wordCount = wordCount ?? PortugueseText.speakableWordCount(text)
    }
}

/// Índice de texto de um material da biblioteca.
public struct LibraryTextIndex: Codable, Hashable, Sendable {

    public static let currentSchemaVersion = 1

    public var itemID: UUID
    public var chunks: [LibraryTextChunk]
    public var totalWordCount: Int
    /// Identificador de idioma (sempre "pt-BR" nesta versão).
    public var languageCode: String
    public var builtAt: Date
    public var schemaVersion: Int

    public init(
        itemID: UUID,
        chunks: [LibraryTextChunk],
        totalWordCount: Int? = nil,
        languageCode: String = "pt-BR",
        builtAt: Date = Date(),
        schemaVersion: Int = LibraryTextIndex.currentSchemaVersion
    ) {
        self.itemID = itemID
        self.chunks = chunks
        self.totalWordCount = totalWordCount ?? chunks.reduce(0) { $0 + $1.wordCount }
        self.languageCode = languageCode
        self.builtAt = builtAt
        self.schemaVersion = schemaVersion
    }

    /// Estimativa de duração de leitura do material inteiro, em minutos.
    public func readingMinutes(wordsPerMinute: Double = SpeechDurationEstimator.defaultWordsPerMinute) -> Double {
        Double(totalWordCount) / (wordsPerMinute > 0 ? wordsPerMinute : SpeechDurationEstimator.defaultWordsPerMinute)
    }

    /// Texto completo (usado em exportação de trechos e diagnóstico).
    public var fullText: String {
        chunks.map(\.text).joined(separator: "\n\n")
    }
}

/// Construtor de índices a partir do conteúdo extraído.
public enum LibraryTextIndexBuilder {

    /// Constrói um índice a partir de capítulos/páginas já extraídos.
    ///
    /// - Parameter units: cada unidade é um capítulo (EPUB), uma página (PDF)
    ///   ou um bloco (texto). Capítulos muito longos são divididos em pedaços
    ///   menores para que o trecho exibido na busca seja útil.
    public static func build(
        itemID: UUID,
        units: [(title: String?, text: String)],
        maximumChunkLength: Int = 4000
    ) -> LibraryTextIndex {
        var chunks: [LibraryTextChunk] = []
        for (index, unit) in units.enumerated() {
            let trimmed = unit.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = split(trimmed, maximumLength: maximumChunkLength)
            var offset = 0
            for part in parts {
                let locator = ReadingLocator.chapter(
                    chapterIndex: index,
                    offset: offset,
                    length: part.count
                )
                chunks.append(LibraryTextChunk(locator: locator, title: unit.title, text: part))
                offset += part.count
            }
        }
        return LibraryTextIndex(itemID: itemID, chunks: chunks)
    }

    /// Divide um texto em pedaços, respeitando limites de parágrafo/frase.
    private static func split(_ text: String, maximumLength: Int) -> [String] {
        guard text.count > maximumLength else { return [text] }
        var parts: [String] = []
        var current = ""
        let paragraphs = text.components(separatedBy: "\n\n")
        for paragraph in paragraphs {
            if current.count + paragraph.count + 2 <= maximumLength {
                current += current.isEmpty ? paragraph : "\n\n" + paragraph
            } else {
                if !current.isEmpty { parts.append(current) }
                if paragraph.count <= maximumLength {
                    current = paragraph
                } else {
                    // Parágrafo gigante: corta por frases.
                    var buffer = ""
                    for sentence in paragraph.components(separatedBy: ". ") {
                        let candidate = buffer.isEmpty ? sentence : buffer + ". " + sentence
                        if candidate.count <= maximumLength {
                            buffer = candidate
                        } else {
                            if !buffer.isEmpty { parts.append(buffer) }
                            buffer = sentence
                        }
                    }
                    current = buffer
                }
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}

/// Um resultado de busca na biblioteca local.
public struct LibrarySearchHit: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var itemID: UUID
    public var itemTitle: String
    public var locator: ReadingLocator?
    public var chapterTitle: String?
    public var snippet: String
    public var score: Double
    /// `true` quando o casamento ocorreu no título do material.
    public var matchedTitle: Bool

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        itemTitle: String,
        locator: ReadingLocator? = nil,
        chapterTitle: String? = nil,
        snippet: String,
        score: Double,
        matchedTitle: Bool = false
    ) {
        self.id = id
        self.itemID = itemID
        self.itemTitle = itemTitle
        self.locator = locator
        self.chapterTitle = chapterTitle
        self.snippet = snippet
        self.score = score
        self.matchedTitle = matchedTitle
    }
}

/// Busca local em materiais indexados.
public enum LibrarySearch {

    /// Pesos usados na pontuação (documentados para tornar o resultado previsível).
    private static let titleMatchScore: Double = 12
    private static let phraseMatchScore: Double = 6
    private static let wordMatchScore: Double = 1.5
    private static let coverageBonus: Double = 4

    /// Pesquisa em um único índice.
    public static func search(
        query: String,
        index: LibraryTextIndex,
        itemTitle: String,
        limit: Int = 50
    ) -> [LibrarySearchHit] {
        let normalizedQuery = PortugueseText.normalizedForSearch(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let queryWords = normalizedQuery.split(separator: " ").map(String.init).filter { $0.count > 1 }
        guard !queryWords.isEmpty else { return [] }

        var hits: [LibrarySearchHit] = []

        // Casamento no título do material.
        if PortugueseText.normalizedForSearch(itemTitle).contains(normalizedQuery) {
            hits.append(LibrarySearchHit(
                itemID: index.itemID,
                itemTitle: itemTitle,
                locator: nil,
                chapterTitle: nil,
                snippet: itemTitle,
                score: titleMatchScore,
                matchedTitle: true
            ))
        }

        for chunk in index.chunks {
            guard let score = scoreChunk(
                chunk.normalizedText,
                phrase: normalizedQuery,
                words: queryWords
            ) else { continue }

            let snippet = makeSnippet(chunk: chunk, phrase: normalizedQuery, words: queryWords)
            hits.append(LibrarySearchHit(
                itemID: index.itemID,
                itemTitle: itemTitle,
                locator: chunk.locator,
                chapterTitle: chunk.title,
                snippet: snippet,
                score: score
            ))
        }

        return Array(hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return (lhs.locator?.chapterIndex ?? 0) < (rhs.locator?.chapterIndex ?? 0)
        }.prefix(limit))
    }

    /// Pesquisa em vários materiais de uma vez.
    public static func search(
        query: String,
        items: [LibraryItem],
        indexes: [UUID: LibraryTextIndex],
        limit: Int = 50
    ) -> [LibrarySearchHit] {
        var hits: [LibrarySearchHit] = []
        for item in items {
            guard let index = indexes[item.id] else { continue }
            hits.append(contentsOf: search(
                query: query,
                index: index,
                itemTitle: item.displayTitle,
                limit: limit
            ))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Pontua um pedaço; devolve `nil` quando não há casamento relevante.
    private static func scoreChunk(_ text: String, phrase: String, words: [String]) -> Double? {
        var score = 0.0
        var matchedWords = 0

        if text.contains(phrase) {
            score += phraseMatchScore
            matchedWords = words.count
        }

        for word in words where text.contains(word) {
            score += wordMatchScore
            matchedWords += 1
        }

        guard score > 0 else { return nil }

        // Exigimos todos os termos quando o pedaço tem todos eles; se o pedaço
        // casar apenas parte da consulta, ele entra com pontuação reduzida
        // (permite encontrar variações), mas nunca substitui um casamento pleno.
        let coverage = words.isEmpty ? 0 : Double(min(matchedWords, words.count)) / Double(words.count)
        if coverage >= 1 {
            score += coverageBonus
        } else {
            score *= coverage
        }
        return score
    }

    /// Cria um trecho em volta do casamento, com destaque implícito ao redor.
    private static func makeSnippet(chunk: LibraryTextChunk, phrase: String, words: [String]) -> String {
        let normalized = chunk.normalizedText
        var offset = 0
        if let range = normalized.range(of: phrase) {
            offset = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
        } else if let word = words.first(where: { normalized.contains($0) }),
                  let range = normalized.range(of: word) {
            offset = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
        }
        return PortugueseText.snippet(in: chunk.text, aroundOffset: offset, maximumLength: 220)
    }
}
