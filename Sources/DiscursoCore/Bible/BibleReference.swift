//
//  BibleReference.swift
//  DiscursoCore
//
//  Modelo de referências bíblicas e geração de links oficiais.
//
//  Uma referência pode ter várias "partes" para representar listas e
//  continuações de capítulos:
//
//      "Romanos 12:1, 2"        -> 1 parte  (cap. 12, versículos 1 e 2)
//      "1 Coríntios 13:4-7"     -> 1 parte  (cap. 13, versículos 4 a 7)
//      "João 3:16; 4:2"         -> 2 partes (cap. 3 v. 16 e cap. 4 v. 2)
//      "João 3"                 -> 1 parte  (capítulo inteiro, sem versículos)
//
//  Os links oficiais são gerados por *número do livro* (ordinal 1...66), um
//  formato estável da Biblioteca On-line (WOL). O aplicativo nunca copia nem
//  armazena o texto bíblico dessas páginas: apenas oferece o link para
//  consulta autorizada na fonte oficial, respeitando direitos autorais.
//

import Foundation

/// Intervalo de versículos dentro de um capítulo.
public struct BibleVerseRange: Hashable, Codable, Sendable {
    /// Primeiro versículo do intervalo.
    public var start: Int
    /// Último versículo do intervalo (igual a `start` quando é um só).
    public var end: Int
    /// Sufixo de versículo parcial, como o "a" de "João 3:16a".
    public var suffix: String?

    public init(start: Int, end: Int? = nil, suffix: String? = nil) {
        self.start = start
        self.end = end ?? start
        self.suffix = suffix
    }

    public var isSingleVerse: Bool { start == end && suffix == nil }

    /// Quantidade de versículos cobertos.
    public var verseCount: Int { max(0, end - start + 1) }

    /// Lista todos os versículos do intervalo.
    public var verses: [Int] { start <= end ? Array(start...end) : [] }

    /// texto de exibição: "16", "4-7", "16a".
    public var displayText: String {
        let base = start == end ? "\(start)" : "\(start)-\(end)"
        return base + (suffix ?? "")
    }
}

/// Parte de uma referência: um capítulo (com ou sem versículos).
public struct BibleReferencePart: Hashable, Codable, Sendable {
    /// Capítulo (>= 1).
    public var chapter: Int
    /// Versículos citados. Lista vazia significa "capítulo inteiro".
    public var verses: [BibleVerseRange]

    public init(chapter: Int, verses: [BibleVerseRange] = []) {
        self.chapter = chapter
        self.verses = verses
    }

    /// `true` quando a referência aponta para o capítulo inteiro.
    public var isWholeChapter: Bool { verses.isEmpty }

    /// Total de versículos citados (0 para capítulo inteiro).
    public var totalVerses: Int { verses.reduce(0) { $0 + $1.verseCount } }

    /// Texto de exibição: "12:1, 2" ou "3".
    public var displayText: String {
        guard !verses.isEmpty else { return "\(chapter)" }
        let list = verses.map(\.displayText).joined(separator: ", ")
        return "\(chapter):\(list)"
    }
}

/// Referência bíblica estruturada (livro + partes).
public struct BibleReference: Hashable, Codable, Sendable {

    /// Livro (ordinal 1...66).
    public var bookID: BibleBookID
    /// Partes da referência, em ordem.
    public var parts: [BibleReferencePart]

    public init(bookID: BibleBookID, parts: [BibleReferencePart]) {
        self.bookID = bookID
        self.parts = parts
    }

    /// Conveniência para referências simples: "João 3:16".
    public init(bookID: BibleBookID, chapter: Int, verseStart: Int? = nil, verseEnd: Int? = nil) {
        if let verseStart {
            let range = BibleVerseRange(start: verseStart, end: verseEnd ?? verseStart)
            self.init(bookID: bookID, parts: [BibleReferencePart(chapter: chapter, verses: [range])])
        } else {
            self.init(bookID: bookID, parts: [BibleReferencePart(chapter: chapter)])
        }
    }

    /// Nome do livro em pt-BR.
    public var bookName: String { BibleBookCatalog.displayName(for: bookID) }

    /// Primeiro capítulo citado (usado em links e navegação).
    public var primaryChapter: Int { parts.first?.chapter ?? 1 }

    /// Todos os capítulos citados, sem repetição e em ordem.
    public var chapterNumbers: [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for part in parts where !seen.contains(part.chapter) {
            seen.insert(part.chapter)
            result.append(part.chapter)
        }
        return result
    }

    /// Primeiro versículo citado, se houver.
    public var firstVerse: Int? { parts.first?.verses.first?.start }

    /// Total de versículos citados (0 para capítulo inteiro).
    public var totalVerses: Int { parts.reduce(0) { $0 + $1.totalVerses } }

    /// Texto de exibição completo: "1 Coríntios 13:4-7".
    public var displayText: String { "\(bookName) \(partsDisplayText)" }

    /// Somente a parte numérica: "13:4-7".
    public var partsDisplayText: String {
        parts.map(\.displayText).joined(separator: "; ")
    }

    /// Abreviação + partes: "1 Cor. 13:4-7".
    public var abbreviatedText: String {
        let abbreviation = BibleBookCatalog.book(ordinal: bookID.rawValue)?.abbreviation ?? bookName
        return "\(abbreviation) \(partsDisplayText)"
    }

    /// Forma "curta" da referência: primeira parte e contagem de extras.
    public var summarizedText: String {
        guard parts.count > 1 else { return displayText }
        return "\(bookName) \(parts[0].displayText) (+\(parts.count - 1))"
    }

    /// Identificadores de versículos no formato usado pela Biblioteca On-line
    /// e pelo app JW Library: livro (2 dígitos) + capítulo (3) + versículo (3).
    public var verseIdentifiers: [String] {
        parts.flatMap { part -> [String] in
            let verses = part.isWholeChapter ? [1] : part.verses.flatMap(\.verses)
            return verses.map { verse in
                String(format: "%02d%03d%03d", bookID.rawValue, part.chapter, verse)
            }
        }
    }

    /// Link para o texto bíblico na Biblioteca On-line (WOL), fonte oficial.
    ///
    /// O texto é consultado no site oficial; nada é copiado para o app.
    public func officialWebURL(languageCode: String = "pt", anchorToVerse: Bool = true) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wol.jw.org"
        components.path = "/\(languageCode)/wol/b/r5/lp-t/nwt/\(bookID.rawValue)/\(primaryChapter)"
        if anchorToVerse, let verse = firstVerse, parts.count == 1, !(parts.first?.isWholeChapter ?? true) {
            components.fragment = "\(verse)"
        }
        return components.url
    }

    /// Link de busca no site oficial JW.ORG para a referência.
    public func officialSearchURL(languageCode: String = "pt") -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.jw.org"
        components.path = "/\(languageCode)/busca/"
        components.queryItems = [URLQueryItem(name: "q", value: displayText)]
        return components.url
    }

    /// Link direto para o aplicativo JW Library, quando instalado.
    ///
    /// Formato público `jwlibrary:///finder?bible=...`. Sempre ofereça o link
    /// da web como alternativa, porque o aplicativo pode não estar instalado.
    public func jwLibraryDeepLink() -> URL? {
        guard let identifier = verseIdentifiers.first else { return nil }
        var components = URLComponents()
        components.scheme = "jwlibrary"
        components.host = ""
        components.path = "/finder"
        components.queryItems = [URLQueryItem(name: "bible", value: identifier)]
        return components.url
    }

    /// Valida a referência contra o catálogo (capítulo existente e versículos >= 1).
    public func isValid() -> Bool {
        guard !parts.isEmpty else { return false }
        for part in parts {
            guard BibleBookCatalog.isValidChapter(part.chapter, in: bookID) else { return false }
            for range in part.verses {
                guard range.start >= 1, range.end >= range.start else { return false }
            }
        }
        return true
    }

    /// Referências relacionadas sugeridas na interface (mesmo capítulo, etc.).
    public var relatedChapterReferences: [BibleReference] {
        chapterNumbers
            .filter { $0 + 1 <= BibleBookCatalog.chapterCount(of: bookID) }
            .map { BibleReference(bookID: bookID, parts: [BibleReferencePart(chapter: $0 + 1)]) }
    }
}
