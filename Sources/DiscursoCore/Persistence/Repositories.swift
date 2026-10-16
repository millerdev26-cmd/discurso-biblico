//
//  Repositories.swift
//  DiscursoCore
//
//  Contratos de persistência.
//
//  A camada de interface (SwiftUI) depende apenas destes protocolos. Isso
//  permite:
//   - usar armazenamento em arquivos (implementação deste pacote, testada);
//   - usar SwiftData no app iOS (índice rápido para listas e buscas);
//   - usar implementações em memória nos testes e nas pré-visualizações.
//

import Foundation

/// Resumo de um discurso, usado em listas (evita carregar o discurso inteiro).
public struct SpeechSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var occasion: String
    public var tags: [String]
    public var folderID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var status: SpeechStatus
    public var isFavorite: Bool
    public var sectionCount: Int
    public var wordCount: Int
    public var estimatedMinutes: Double
    public var plannedMinutes: Double?
    public var referenceCount: Int
    public var sourceCount: Int
    public var preparationProgress: Double
    public var lastReadSectionTitle: String?
    public var lastReadFraction: Double?

    public init(
        id: UUID,
        title: String,
        subtitle: String = "",
        occasion: String = "",
        tags: [String] = [],
        folderID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date,
        status: SpeechStatus,
        isFavorite: Bool,
        sectionCount: Int,
        wordCount: Int,
        estimatedMinutes: Double,
        plannedMinutes: Double? = nil,
        referenceCount: Int = 0,
        sourceCount: Int = 0,
        preparationProgress: Double = 0,
        lastReadSectionTitle: String? = nil,
        lastReadFraction: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.occasion = occasion
        self.tags = tags
        self.folderID = folderID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.isFavorite = isFavorite
        self.sectionCount = sectionCount
        self.wordCount = wordCount
        self.estimatedMinutes = estimatedMinutes
        self.plannedMinutes = plannedMinutes
        self.referenceCount = referenceCount
        self.sourceCount = sourceCount
        self.preparationProgress = preparationProgress
        self.lastReadSectionTitle = lastReadSectionTitle
        self.lastReadFraction = lastReadFraction
    }

    public init(speech: Speech) {
        let position = speech.lastReadPosition
        let sectionTitle = position?.resolvedSectionIndex(in: speech).map { speech.sections[$0].displayTitle }
        self.init(
            id: speech.id,
            title: speech.displayTitle,
            subtitle: speech.subtitle,
            occasion: speech.occasion,
            tags: speech.tags,
            folderID: speech.folderID,
            createdAt: speech.createdAt,
            updatedAt: speech.updatedAt,
            status: speech.status,
            isFavorite: speech.isFavorite,
            sectionCount: speech.sections.count,
            wordCount: speech.wordCount,
            estimatedMinutes: speech.estimatedMinutes,
            plannedMinutes: speech.plannedMinutes,
            referenceCount: speech.references.count,
            sourceCount: speech.allSources.count,
            preparationProgress: speech.preparationProgress,
            lastReadSectionTitle: sectionTitle,
            lastReadFraction: position?.scrollFraction
        )
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Discurso sem título" : trimmed
    }

    /// Duração usada para exibição (planejada, quando existir).
    public var displayMinutes: Double {
        plannedMinutes ?? estimatedMinutes
    }

    public var isPreparing: Bool { status == .preparing }
}

/// Aviso gerado pela camada de armazenamento (ex.: recuperação de cópia).
public struct RepositoryWarning: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var message: String
    public var date: Date

    public init(id: UUID = UUID(), message: String, date: Date = Date()) {
        self.id = id
        self.message = message
        self.date = date
    }
}

/// Armazenamento de discursos e pastas.
public protocol SpeechRepository: Sendable {
    func loadSummaries() async throws -> [SpeechSummary]
    func load(id: UUID) async throws -> Speech
    func loadAll() async throws -> [Speech]
    func save(_ speech: Speech) async throws
    func delete(id: UUID) async throws
    func folders() async throws -> [SpeechFolder]
    func saveFolders(_ folders: [SpeechFolder]) async throws
    /// Avisos acumulados (recuperações, arquivos corrompidos contornados).
    func takeWarnings() async -> [RepositoryWarning]
}

/// Armazenamento dos materiais da biblioteca e de seus índices de texto.
public protocol LibraryRepository: Sendable {
    func loadItems() async throws -> [LibraryItem]
    func load(id: UUID) async throws -> LibraryItem?
    func save(_ item: LibraryItem) async throws
    func delete(id: UUID) async throws
    /// Copia o arquivo escolhido pelo usuário para a área do aplicativo.
    /// - Returns: o nome do arquivo armazenado.
    func storeFile(from sourceURL: URL, itemID: UUID, fileExtension: String) async throws -> String
    /// URL do arquivo do material na área do aplicativo.
    func fileURL(for item: LibraryItem) async -> URL?
    func saveIndex(_ index: LibraryTextIndex, for itemID: UUID) async throws
    func loadIndex(for itemID: UUID) async throws -> LibraryTextIndex?
    func deleteIndex(for itemID: UUID) async throws
}

/// Armazenamento das pesquisas salvas, histórico e cache de resultados.
public protocol ResearchRepository: Sendable {
    func savedResearch() async throws -> [SavedResearch]
    func save(_ item: SavedResearch) async throws
    func deleteSavedResearch(id: UUID) async throws
    func searchHistory() async throws -> [SearchHistoryEntry]
    func record(_ entry: SearchHistoryEntry) async throws
    func clearSearchHistory() async throws
    func cachedResults(forKey key: String) async throws -> CachedResearchResults?
    func cache(_ results: CachedResearchResults, forKey key: String) async throws
    func clearCache() async throws
}

/// Resultados de pesquisa guardados em cache local.
public struct CachedResearchResults: Codable, Hashable, Sendable {
    public var query: String
    public var providerID: String
    public var results: [ResearchResultPayload]
    public var storedAt: Date

    public init(query: String, providerID: String, results: [ResearchResultPayload], storedAt: Date = Date()) {
        self.query = query
        self.providerID = providerID
        self.results = results
        self.storedAt = storedAt
    }

    public func isFresh(lifetime: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(storedAt) < lifetime
    }
}

/// Armazenamento das configurações e dos perfis de leitura.
public protocol SettingsRepository: Sendable {
    func settings() async throws -> AppSettings
    func save(_ settings: AppSettings) async throws
    func readingProfiles() async throws -> [ReadingProfile]
    func save(_ profiles: [ReadingProfile]) async throws
}
