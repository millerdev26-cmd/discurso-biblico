//
//  BibleTextProvider.swift
//  DiscursoCore
//
//  Camada de provedores de texto bíblico.
//
//  Princípios (requisito do projeto):
//   1. o aplicativo **não redistribui** traduções da Bíblia;
//   2. quando o usuário quer o texto, ele é consultado na fonte oficial
//      (link) ou vem de um arquivo que **ele mesmo** importou;
//   3. nenhum texto é inventado: sem fonte, o trecho simplesmente não existe.
//
//  A interface sempre consegue oferecer: (a) o link oficial para o capítulo;
//  (b) o atalho para o aplicativo JW Library, quando instalado.
//

import Foundation

/// Versículo pronto para exibição.
public struct BibleVerse: Codable, Hashable, Sendable {
    public var number: Int
    public var text: String

    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }
}

/// Trecho bíblico obtido de um provedor.
public struct BiblePassage: Hashable, Sendable {
    public var reference: BibleReference
    /// Versículos disponíveis (vazio quando o provedor só oferece links).
    public var verses: [BibleVerse]
    /// Nome da fonte ("Arquivo importado pelo usuário" etc.).
    public var sourceName: String?
    /// Link para consulta oficial.
    public var officialURL: URL?
    /// Atalho para o aplicativo JW Library, quando aplicável.
    public var deepLink: URL?
    /// Aviso honesto para a interface (ex.: "texto consultado na fonte oficial").
    public var notice: String?
    /// Referências pedidas que não existem no provedor.
    public var missingVerseNumbers: [Int]

    public init(
        reference: BibleReference,
        verses: [BibleVerse] = [],
        sourceName: String? = nil,
        officialURL: URL? = nil,
        deepLink: URL? = nil,
        notice: String? = nil,
        missingVerseNumbers: [Int] = []
    ) {
        self.reference = reference
        self.verses = verses
        self.sourceName = sourceName
        self.officialURL = officialURL
        self.deepLink = deepLink
        self.notice = notice
        self.missingVerseNumbers = missingVerseNumbers
    }

    public var isEmpty: Bool { verses.isEmpty }

    /// Texto corrido dos versículos ("16 Texto. 17 Texto.").
    public var plainText: String {
        verses.map { "\($0.number) \($0.text)" }.joined(separator: " ")
    }

    /// Versículo por número.
    public func verse(number: Int) -> BibleVerse? {
        verses.first { $0.number == number }
    }
}

/// Erros da camada de texto bíblico.
public enum BibleTextError: LocalizedError, Equatable {
    case invalidReference(String)
    case textUnavailable(String)
    case providerUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReference(let reason):
            return "A referência bíblica não é válida (\(reason))."
        case .textUnavailable(let reference):
            return "O texto de \(reference) não está disponível localmente."
        case .providerUnavailable(let name):
            return "A fonte de texto bíblico \(name) não está disponível."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .textUnavailable:
            return "Consulte o texto na fonte oficial (link) ou importe um arquivo com o texto que você tem direito de usar."
        default:
            return nil
        }
    }
}

/// Contrato de um provedor de texto bíblico.
public protocol BibleTextProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func passage(for reference: BibleReference) async throws -> BiblePassage
}

// MARK: - Provedor de links oficiais

/// Provedor padrão: nunca devolve texto, mas devolve os links oficiais.
///
/// É o provedor usado quando o usuário ainda não importou nenhum texto.
public struct OfficialLinkBibleProvider: BibleTextProvider {

    public nonisolated var id: String { "bible.official.links" }
    public nonisolated var displayName: String { "Consulta na fonte oficial" }

    public init() {}

    public func passage(for reference: BibleReference) async throws -> BiblePassage {
        guard reference.isValid() else {
            throw BibleTextError.invalidReference(reference.displayText)
        }
        return BiblePassage(
            reference: reference,
            verses: [],
            sourceName: "Fonte oficial (link)",
            officialURL: reference.officialWebURL(),
            deepLink: reference.jwLibraryDeepLink(),
            notice: "O texto bíblico não é armazenado no aplicativo. Use o link para consultá-lo na fonte oficial."
        )
    }
}

// MARK: - Provedor local

/// Fonte de texto bíblico importada pelo próprio usuário.
///
/// O armazenamento é injetado: nos testes, um dicionário em memória; no
/// aplicativo, os arquivos que o usuário importar para a pasta `bible/`.
public protocol BibleTextStore: Sendable {
    /// Versículos de um capítulo (número do versículo → texto).
    func verses(bookID: BibleBookID, chapter: Int) async -> [Int: String]
}

/// Dicionário em memória (testes e pré-visualizações).
public struct InMemoryBibleTextStore: BibleTextStore {
    private let texts: [String: [Int: String]]

    public init(texts: [String: [Int: String]]) {
        self.texts = texts
    }

    public init(verses: [BibleBookID: [Int: [Int: String]]]) {
        var map: [String: [Int: String]] = [:]
        for (bookID, chapters) in verses {
            for (chapter, verses) in chapters {
                map["\(bookID.rawValue)-\(chapter)"] = verses
            }
        }
        self.texts = map
    }

    public func verses(bookID: BibleBookID, chapter: Int) async -> [Int: String] {
        texts["\(bookID.rawValue)-\(chapter)"] ?? [:]
    }
}

/// Provedor que serve apenas o texto que o usuário importou.
public struct LocalBibleTextProvider: BibleTextProvider {

    public nonisolated var id: String { "bible.local.imported" }
    public nonisolated var displayName: String { "Texto importado pelo usuário" }

    private let store: any BibleTextStore
    private let sourceName: String

    public init(store: any BibleTextStore, sourceName: String = "Texto importado") {
        self.store = store
        self.sourceName = sourceName
    }

    public func passage(for reference: BibleReference) async throws -> BiblePassage {
        guard reference.isValid() else {
            throw BibleTextError.invalidReference(reference.displayText)
        }

        var verses: [BibleVerse] = []
        var missing: [Int] = []

        for part in reference.parts {
            let chapterText = await store.verses(bookID: reference.bookID, chapter: part.chapter)
            if part.isWholeChapter {
                for number in chapterText.keys.sorted() {
                    let text = chapterText[number] ?? ""
                    guard Self.hasVisibleText(text) else { continue }
                    verses.append(BibleVerse(number: number, text: text))
                }
                continue
            }
            for range in part.verses {
                for number in range.verses {
                    if let text = chapterText[number], Self.hasVisibleText(text) {
                        verses.append(BibleVerse(number: number, text: text))
                    } else {
                        missing.append(number)
                    }
                }
            }
        }

        // A ordem de coleta já é a ordem de leitura (partes da referência,
        // capítulos e intervalos na ordem em que foram escritos).
        if verses.isEmpty {
            throw BibleTextError.textUnavailable(reference.displayText)
        }

        var notice: String? = nil
        if !missing.isEmpty {
            let list = missing.map(String.init).joined(separator: ", ")
            notice = "Versículos não encontrados no texto importado: \(list). Use o link oficial para completar."
        }

        return BiblePassage(
            reference: reference,
            verses: verses,
            sourceName: sourceName,
            officialURL: reference.officialWebURL(),
            deepLink: reference.jwLibraryDeepLink(),
            notice: notice,
            missingVerseNumbers: missing
        )
    }

    /// `true` quando o texto tem conteúdo visível (espaços em branco, sozinhos,
    /// não contam como versículo disponível).
    private static func hasVisibleText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
