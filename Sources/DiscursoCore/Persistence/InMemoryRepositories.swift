//
//  InMemoryRepositories.swift
//  DiscursoCore
//
//  Implementações em memória dos repositórios.
//
//  Usadas nos testes automatizados e nas pré-visualizações do SwiftUI, e também
//  como referência de comportamento para a implementação com SwiftData no app.
//  Elas compartilham os mesmos contratos, portanto os testes exercitam
//  exatamente as chamadas que a interface faz.
//

import Foundation

/// Repositório de discursos em memória.
public actor InMemorySpeechRepository: SpeechRepository {

    private var speeches: [UUID: Speech]
    private var storedFolders: [SpeechFolder]
    private var warnings: [RepositoryWarning] = []

    public init(speeches: [Speech] = [], folders: [SpeechFolder] = []) {
        self.speeches = Dictionary(uniqueKeysWithValues: speeches.map { ($0.id, $0) })
        self.storedFolders = folders
    }

    public func loadSummaries() async throws -> [SpeechSummary] {
        speeches.values.map(SpeechSummary.init(speech:)).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func load(id: UUID) async throws -> Speech {
        guard let speech = speeches[id] else { throw DocumentStoreError.notFound(id.uuidString) }
        return speech
    }

    public func loadAll() async throws -> [Speech] {
        speeches.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ speech: Speech) async throws {
        var updated = speech
        updated.presentation = updated.presentation.sanitized()
        speeches[updated.id] = updated
    }

    public func delete(id: UUID) async throws {
        speeches.removeValue(forKey: id)
    }

    public func folders() async throws -> [SpeechFolder] {
        storedFolders.sorted { $0.sortIndex < $1.sortIndex }
    }

    public func saveFolders(_ folders: [SpeechFolder]) async throws {
        storedFolders = folders
    }

    public func takeWarnings() async -> [RepositoryWarning] {
        let current = warnings
        warnings.removeAll()
        return current
    }

    /// Simula um aviso de armazenamento (usado em testes de recuperação).
    public func injectWarning(_ message: String) {
        warnings.append(RepositoryWarning(message: message))
    }
}

/// Repositório de biblioteca em memória (não copia arquivos reais).
public actor InMemoryLibraryRepository: LibraryRepository {

    private var items: [UUID: LibraryItem]
    private var indexes: [UUID: LibraryTextIndex] = [:]
    private let baseDirectory: URL
    private let fileManager: FileManager

    public init(items: [LibraryItem] = [], baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
            ?? fileManager.temporaryDirectory.appendingPathComponent("discurso-memory-\(UUID().uuidString)")
    }

    public func loadItems() async throws -> [LibraryItem] {
        items.values.sorted { $0.importedAt > $1.importedAt }
    }

    public func load(id: UUID) async throws -> LibraryItem? {
        items[id]
    }

    public func save(_ item: LibraryItem) async throws {
        items[item.id] = item
    }

    public func delete(id: UUID) async throws {
        if let item = items[id] {
            let url = baseDirectory.appendingPathComponent(item.fileName)
            try? fileManager.removeItem(at: url)
        }
        indexes.removeValue(forKey: id)
        items.removeValue(forKey: id)
    }

    public func storeFile(from sourceURL: URL, itemID: UUID, fileExtension: String) async throws -> String {
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let fileName = "\(itemID.uuidString.lowercased()).\(fileExtension.lowercased())"
        let destination = baseDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            throw DocumentStoreError.writeFailed(file: fileName, reason: error.localizedDescription)
        }
        return fileName
    }

    public func fileURL(for item: LibraryItem) async -> URL? {
        let url = baseDirectory.appendingPathComponent(item.fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func saveIndex(_ index: LibraryTextIndex, for itemID: UUID) async throws {
        indexes[itemID] = index
    }

    public func loadIndex(for itemID: UUID) async throws -> LibraryTextIndex? {
        indexes[itemID]
    }

    public func deleteIndex(for itemID: UUID) async throws {
        indexes.removeValue(forKey: itemID)
    }

    /// Índices em memória, usado pelo serviço de pesquisa local.
    public func allIndexes() -> [UUID: LibraryTextIndex] { indexes }
}

/// Repositório de pesquisa em memória.
public actor InMemoryResearchRepository: ResearchRepository {

    private var saved: [SavedResearch]
    private var history: [SearchHistoryEntry]
    private var cache: [String: CachedResearchResults] = [:]

    public init(saved: [SavedResearch] = [], history: [SearchHistoryEntry] = []) {
        self.saved = saved.sorted { $0.savedAt > $1.savedAt }
        self.history = history
    }

    public func savedResearch() async throws -> [SavedResearch] {
        saved.sorted { $0.savedAt > $1.savedAt }
    }

    public func save(_ item: SavedResearch) async throws {
        if let index = saved.firstIndex(where: { $0.id == item.id }) {
            saved[index] = item
        } else {
            saved.insert(item, at: 0)
        }
    }

    public func deleteSavedResearch(id: UUID) async throws {
        saved.removeAll { $0.id == id }
    }

    public func searchHistory() async throws -> [SearchHistoryEntry] {
        history.sorted { $0.searchedAt > $1.searchedAt }
    }

    public func record(_ entry: SearchHistoryEntry) async throws {
        history.insert(entry, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
    }

    public func clearSearchHistory() async throws {
        history.removeAll()
    }

    public func cachedResults(forKey key: String) async throws -> CachedResearchResults? {
        cache[key]
    }

    public func cache(_ results: CachedResearchResults, forKey key: String) async throws {
        cache[key] = results
    }

    public func clearCache() async throws {
        cache.removeAll()
    }
}

/// Repositório de configurações em memória.
public actor InMemorySettingsRepository: SettingsRepository {

    private var storedSettings: AppSettings
    private var storedProfiles: [ReadingProfile]

    public init(settings: AppSettings = .default, profiles: [ReadingProfile] = ReadingProfile.builtInProfiles) {
        self.storedSettings = settings
        self.storedProfiles = profiles
    }

    public func settings() async throws -> AppSettings {
        storedSettings.sanitized()
    }

    public func save(_ settings: AppSettings) async throws {
        storedSettings = settings.sanitized()
    }

    public func readingProfiles() async throws -> [ReadingProfile] {
        storedProfiles
    }

    public func save(_ profiles: [ReadingProfile]) async throws {
        storedProfiles = profiles
    }
}
