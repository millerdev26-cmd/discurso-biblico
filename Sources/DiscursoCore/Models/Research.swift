//
//  Research.swift
//  DiscursoCore
//
//  Modelos da área de pesquisa: resultados, favoritos e histórico.
//
//  Os resultados vêm de provedores isolados (ver pasta `Research`): pesquisa
//  local na biblioteca, pesquisa em páginas públicas oficiais e links diretos
//  para a fonte oficial. O modelo abaixo é comum a todos eles, o que permite
//  trocar um provedor sem tocar na interface.
//

import Foundation

/// Tipo de material encontrado na pesquisa.
public enum ResearchMaterialKind: String, Codable, CaseIterable, Sendable {
    case article
    case publication
    case book
    case magazine
    case video
    case audio
    case scripture
    case localDocument
    case unknown

    public var displayName: String {
        switch self {
        case .article: return "Artigo"
        case .publication: return "Publicação"
        case .book: return "Livro"
        case .magazine: return "Revista"
        case .video: return "Vídeo"
        case .audio: return "Áudio"
        case .scripture: return "Texto bíblico"
        case .localDocument: return "Material importado"
        case .unknown: return "Material"
        }
    }

    public var systemImageName: String {
        switch self {
        case .article: return "doc.text"
        case .publication: return "books.vertical"
        case .book: return "book"
        case .magazine: return "newspaper"
        case .video: return "play.rectangle"
        case .audio: return "waveform"
        case .scripture: return "book.closed"
        case .localDocument: return "folder"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Um resultado de pesquisa.
public struct ResearchResult: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Identificador do provedor que encontrou o resultado.
    public var providerID: String
    public var title: String
    /// Publicação ou veículo de origem.
    public var publication: String?
    /// Resumo/trecho disponível publicamente.
    public var snippet: String?
    /// Endereço original do conteúdo.
    public var url: URL?
    /// Material da biblioteca local, quando o resultado vem de lá.
    public var libraryItemID: UUID?
    /// Localizador dentro do material local.
    public var locator: ReadingLocator?
    public var kind: ResearchMaterialKind
    /// Data da consulta.
    public var accessedAt: Date
    /// Relevância (quanto maior, melhor) usada para ordenar resultados.
    public var score: Double
    /// Indica se o conteúdo pode ser lido dentro do aplicativo.
    public var isAvailableOffline: Bool

    public init(
        id: UUID = UUID(),
        providerID: String,
        title: String,
        publication: String? = nil,
        snippet: String? = nil,
        url: URL? = nil,
        libraryItemID: UUID? = nil,
        locator: ReadingLocator? = nil,
        kind: ResearchMaterialKind = .unknown,
        accessedAt: Date = Date(),
        score: Double = 0,
        isAvailableOffline: Bool = false
    ) {
        self.id = id
        self.providerID = providerID
        self.title = title
        self.publication = publication
        self.snippet = snippet
        self.url = url
        self.libraryItemID = libraryItemID
        self.locator = locator
        self.kind = kind
        self.accessedAt = accessedAt
        self.score = score
        self.isAvailableOffline = isAvailableOffline
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (url?.absoluteString ?? "Resultado sem título") : trimmed
    }

    /// Converte o resultado em uma fonte que pode ser associada a um discurso.
    public func asSourceLink(note: String? = nil) -> SourceLink {
        SourceLink(
            title: displayTitle,
            url: url,
            kind: libraryItemID != nil ? .localItem : .onlinePublication,
            publication: publication,
            excerpt: snippet,
            note: note,
            libraryItemID: libraryItemID,
            locator: locator,
            accessedAt: accessedAt
        )
    }
}

/// Pesquisa guardada como favorita, com notas e vínculos.
public struct SavedResearch: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Termo pesquisado.
    public var query: String
    /// Resultado salvo.
    public var result: ResearchResultPayload
    /// Nota pessoal sobre a fonte.
    public var note: String
    public var tags: [String]
    /// Discursos aos quais esta fonte foi associada.
    public var linkedSpeechIDs: [UUID]
    public var savedAt: Date

    public init(
        id: UUID = UUID(),
        query: String,
        result: ResearchResultPayload,
        note: String = "",
        tags: [String] = [],
        linkedSpeechIDs: [UUID] = [],
        savedAt: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.result = result
        self.note = note
        self.tags = tags
        self.linkedSpeechIDs = linkedSpeechIDs
        self.savedAt = savedAt
    }
}

/// Versão codificável de `ResearchResult` (URL como texto).
public struct ResearchResultPayload: Codable, Hashable, Sendable {
    public var providerID: String
    public var title: String
    public var publication: String?
    public var snippet: String?
    public var urlString: String?
    public var libraryItemID: UUID?
    public var locator: ReadingLocator?
    public var kind: ResearchMaterialKind
    public var accessedAt: Date

    public init(
        providerID: String,
        title: String,
        publication: String? = nil,
        snippet: String? = nil,
        urlString: String? = nil,
        libraryItemID: UUID? = nil,
        locator: ReadingLocator? = nil,
        kind: ResearchMaterialKind = .unknown,
        accessedAt: Date = Date()
    ) {
        self.providerID = providerID
        self.title = title
        self.publication = publication
        self.snippet = snippet
        self.urlString = urlString
        self.libraryItemID = libraryItemID
        self.locator = locator
        self.kind = kind
        self.accessedAt = accessedAt
    }

    public init(result: ResearchResult) {
        self.init(
            providerID: result.providerID,
            title: result.title,
            publication: result.publication,
            snippet: result.snippet,
            urlString: result.url?.absoluteString,
            libraryItemID: result.libraryItemID,
            locator: result.locator,
            kind: result.kind,
            accessedAt: result.accessedAt
        )
    }

    public var url: URL? { urlString.flatMap(URL.init(string:)) }

    /// Reconstitui o resultado para exibição na lista de favoritos.
    public func asResearchResult() -> ResearchResult {
        ResearchResult(
            providerID: providerID,
            title: title,
            publication: publication,
            snippet: snippet,
            url: url,
            libraryItemID: libraryItemID,
            locator: locator,
            kind: kind,
            accessedAt: accessedAt,
            score: 0,
            isAvailableOffline: libraryItemID != nil
        )
    }

    /// Converte em fonte associável a um discurso.
    public func asSourceLink(note: String? = nil) -> SourceLink {
        SourceLink(
            title: title,
            url: url,
            kind: libraryItemID != nil ? .localItem : .onlinePublication,
            publication: publication,
            excerpt: snippet,
            note: note,
            libraryItemID: libraryItemID,
            locator: locator,
            accessedAt: accessedAt
        )
    }
}

/// Registro do histórico de pesquisas.
public struct SearchHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var query: String
    /// Provedores consultados.
    public var providerIDs: [String]
    public var resultCount: Int
    public var searchedAt: Date
    /// `true` quando a pesquisa falhou (rede indisponível, por exemplo).
    public var failed: Bool
    /// Mensagem de erro exibida ao usuário.
    public var failureMessage: String?

    public init(
        id: UUID = UUID(),
        query: String,
        providerIDs: [String] = [],
        resultCount: Int = 0,
        searchedAt: Date = Date(),
        failed: Bool = false,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.query = query
        self.providerIDs = providerIDs
        self.resultCount = resultCount
        self.searchedAt = searchedAt
        self.failed = failed
        self.failureMessage = failureMessage
    }
}

/// Situação de uma pesquisa (usada pela interface para mostrar estados claros).
public enum ResearchStatus: Equatable, Sendable {
    case idle
    case loading
    case success
    case empty
    case offline
    case failed(String)

    public var isBusy: Bool { self == .loading }

    public var message: String? {
        switch self {
        case .idle, .success, .loading: return nil
        case .empty: return "Nenhum resultado encontrado. Tente outras palavras ou uma referência bíblica."
        case .offline: return "Sem conexão. A pesquisa local continua disponível."
        case .failed(let reason): return reason
        }
    }
}
