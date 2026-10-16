//
//  SwiftDataRepositories.swift
//  DiscursoBiblico
//
//  Implementações dos protocolos de persistência do `DiscursoCore` sobre o
//  SwiftData. Cada armazenamento é um `@ModelActor` (com o próprio contexto,
//  isolado do ator principal) e a classe de repositório apenas encaminha as
//  chamadas — assim a interface continua falando apenas com os protocolos do
//  núcleo, exatamente como nos testes em Linux.
//

import DiscursoCore
import Foundation
import SwiftData

// MARK: - Discursos

@ModelActor
actor SpeechDataStore {

    private var warnings: [RepositoryWarning] = []

    func loadSummaries() throws -> [SpeechSummary] {
        let descriptor = FetchDescriptor<SpeechRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.summary)
    }

    func load(id: UUID) throws -> Speech? {
        try record(id: id)?.speech
    }

    func loadAll() throws -> [Speech] {
        let descriptor = FetchDescriptor<SpeechRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap(\.speech)
    }

    func save(_ speech: Speech) throws {
        if let existing = try record(id: speech.id) {
            existing.update(with: speech)
        } else {
            modelContext.insert(SpeechRecord(speech: speech))
        }
        try modelContext.save()
    }

    func delete(id: UUID) throws {
        if let existing = try record(id: id) {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    func folders() throws -> [SpeechFolder] {
        let descriptor = FetchDescriptor<SpeechFolderRecord>(
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return try modelContext.fetch(descriptor).compactMap(\.folder)
    }

    func saveFolders(_ folders: [SpeechFolder]) throws {
        let existing = try modelContext.fetch(FetchDescriptor<SpeechFolderRecord>())
        var byID: [UUID: SpeechFolderRecord] = [:]
        for record in existing { byID[record.id] = record }
        var keep = Set<UUID>()
        for folder in folders {
            keep.insert(folder.id)
            if let record = byID[folder.id] {
                record.update(with: folder)
            } else {
                modelContext.insert(SpeechFolderRecord(folder: folder))
            }
        }
        for record in existing where !keep.contains(record.id) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    func note(_ message: String) {
        warnings.append(RepositoryWarning(message: message))
    }

    func takeWarnings() -> [RepositoryWarning] {
        defer { warnings.removeAll() }
        return warnings
    }

    private func record(id: UUID) throws -> SpeechRecord? {
        var descriptor = FetchDescriptor<SpeechRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

final class SwiftDataSpeechRepository: SpeechRepository, @unchecked Sendable {

    private let store: SpeechDataStore

    init(store: SpeechDataStore) {
        self.store = store
    }

    func loadSummaries() async throws -> [SpeechSummary] { try await store.loadSummaries() }
    func load(id: UUID) async throws -> Speech {
        guard let speech = try await store.load(id: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return speech
    }
    func loadAll() async throws -> [Speech] { try await store.loadAll() }
    func save(_ speech: Speech) async throws { try await store.save(speech) }
    func delete(id: UUID) async throws { try await store.delete(id: id) }
    func folders() async throws -> [SpeechFolder] { try await store.folders() }
    func saveFolders(_ folders: [SpeechFolder]) async throws { try await store.saveFolders(folders) }
    func takeWarnings() async -> [RepositoryWarning] { await store.takeWarnings() }

    /// Registra um aviso para a interface (usado na importação e na leitura).
    func note(_ message: String) async { await store.note(message) }
}

// MARK: - Biblioteca

@ModelActor
actor LibraryDataStore {

    func loadItems() throws -> [LibraryItem] {
        let descriptor = FetchDescriptor<LibraryItemRecord>(
            sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap(\.item)
    }

    func load(id: UUID) throws -> LibraryItem? {
        try record(id: id)?.item
    }

    func save(_ item: LibraryItem) throws {
        if let existing = try record(id: item.id) {
            existing.update(with: item)
        } else {
            modelContext.insert(LibraryItemRecord(item: item))
        }
        try modelContext.save()
    }

    func delete(id: UUID) throws {
        if let existing = try record(id: id) {
            modelContext.delete(existing)
        }
        if let indexRecord = try indexRecord(itemID: id) {
            modelContext.delete(indexRecord)
        }
        try modelContext.save()
    }

    func saveIndex(_ index: LibraryTextIndex, for itemID: UUID) throws {
        if let existing = try indexRecord(itemID: itemID) {
            existing.update(with: index)
        } else {
            modelContext.insert(LibraryIndexRecord(index: index))
        }
        try modelContext.save()
    }

    func loadIndex(for itemID: UUID) throws -> LibraryTextIndex? {
        try indexRecord(itemID: itemID)?.index
    }

    func deleteIndex(for itemID: UUID) throws {
        if let existing = try indexRecord(itemID: itemID) {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    private func record(id: UUID) throws -> LibraryItemRecord? {
        var descriptor = FetchDescriptor<LibraryItemRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func indexRecord(itemID: UUID) throws -> LibraryIndexRecord? {
        var descriptor = FetchDescriptor<LibraryIndexRecord>(
            predicate: #Predicate { $0.itemID == itemID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

final class SwiftDataLibraryRepository: LibraryRepository, @unchecked Sendable {

    private let store: LibraryDataStore
    private let files: LibraryFileStore

    init(store: LibraryDataStore, files: LibraryFileStore) {
        self.store = store
        self.files = files
    }

    func loadItems() async throws -> [LibraryItem] { try await store.loadItems() }
    func load(id: UUID) async throws -> LibraryItem? { try await store.load(id: id) }
    func save(_ item: LibraryItem) async throws { try await store.save(item) }

    func delete(id: UUID) async throws {
        if let item = try await store.load(id: id) {
            files.removeFile(for: item)
        }
        try await store.delete(id: id)
    }

    func storeFile(from sourceURL: URL, itemID: UUID, fileExtension: String) async throws -> String {
        try files.store(copying: sourceURL, itemID: itemID, fileExtension: fileExtension)
    }

    func fileURL(for item: LibraryItem) async -> URL? {
        let url = files.fileURL(for: item)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func saveIndex(_ index: LibraryTextIndex, for itemID: UUID) async throws {
        try await store.saveIndex(index, for: itemID)
    }

    func loadIndex(for itemID: UUID) async throws -> LibraryTextIndex? {
        try await store.loadIndex(for: itemID)
    }

    func deleteIndex(for itemID: UUID) async throws {
        try await store.deleteIndex(for: itemID)
    }
}

// MARK: - Pesquisa

@ModelActor
actor ResearchDataStore {

    func savedResearch() throws -> [SavedResearch] {
        let descriptor = FetchDescriptor<SavedResearchRecord>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap(\.saved)
    }

    func save(_ item: SavedResearch) throws {
        if let existing = try savedRecord(id: item.id) {
            existing.update(with: item)
        } else {
            modelContext.insert(SavedResearchRecord(saved: item))
        }
        try modelContext.save()
    }

    func deleteSavedResearch(id: UUID) throws {
        if let existing = try savedRecord(id: id) {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    func searchHistory() throws -> [SearchHistoryEntry] {
        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap(\.entry)
    }

    func record(_ entry: SearchHistoryEntry) throws {
        modelContext.insert(SearchHistoryRecord(entry: entry))
        try modelContext.save()
        try pruneHistory()
    }

    func clearSearchHistory() throws {
        for record in try modelContext.fetch(FetchDescriptor<SearchHistoryRecord>()) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    func cachedResults(forKey key: String) throws -> CachedResearchResults? {
        try cacheRecord(key: key)?.cached
    }

    func cache(_ results: CachedResearchResults, forKey key: String) throws {
        if let existing = try cacheRecord(key: key) {
            existing.update(with: results)
        } else {
            modelContext.insert(CachedResearchRecord(key: key, cached: results))
        }
        try modelContext.save()
    }

    func clearCache() throws {
        for record in try modelContext.fetch(FetchDescriptor<CachedResearchRecord>()) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    /// Mantém as 200 pesquisas mais recentes (as demais são descartadas).
    private func pruneHistory() throws {
        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        guard all.count > 200 else { return }
        for record in all.dropFirst(200) { modelContext.delete(record) }
        try modelContext.save()
    }

    private func savedRecord(id: UUID) throws -> SavedResearchRecord? {
        var descriptor = FetchDescriptor<SavedResearchRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func cacheRecord(key: String) throws -> CachedResearchRecord? {
        var descriptor = FetchDescriptor<CachedResearchRecord>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

final class SwiftDataResearchRepository: ResearchRepository, @unchecked Sendable {

    private let store: ResearchDataStore

    init(store: ResearchDataStore) {
        self.store = store
    }

    func savedResearch() async throws -> [SavedResearch] { try await store.savedResearch() }
    func save(_ item: SavedResearch) async throws { try await store.save(item) }
    func deleteSavedResearch(id: UUID) async throws { try await store.deleteSavedResearch(id: id) }
    func searchHistory() async throws -> [SearchHistoryEntry] { try await store.searchHistory() }
    func record(_ entry: SearchHistoryEntry) async throws { try await store.record(entry) }
    func clearSearchHistory() async throws { try await store.clearSearchHistory() }
    func cachedResults(forKey key: String) async throws -> CachedResearchResults? {
        try await store.cachedResults(forKey: key)
    }
    func cache(_ results: CachedResearchResults, forKey key: String) async throws {
        try await store.cache(results, forKey: key)
    }
    func clearCache() async throws { try await store.clearCache() }
}

// MARK: - Configurações

@ModelActor
actor SettingsDataStore {

    func settings() throws -> AppSettings {
        let record = try settingsRecord()
        return record?.settings ?? .default
    }

    func save(_ settings: AppSettings) throws {
        if let record = try settingsRecord() {
            record.update(with: settings)
        } else {
            modelContext.insert(SettingsRecord(settings: settings))
        }
        try modelContext.save()
    }

    func readingProfiles() throws -> [ReadingProfile] {
        let descriptor = FetchDescriptor<ReadingProfileRecord>(
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        let stored = try modelContext.fetch(descriptor).compactMap(\.profile)
        guard stored.isEmpty else { return stored }

        // Primeira execução: grava os perfis sugeridos para que o usuário
        // possa editá-los como qualquer outro.
        let builtIn = ReadingProfile.builtInProfiles
        for (index, profile) in builtIn.enumerated() {
            modelContext.insert(ReadingProfileRecord(profile: profile, sortIndex: index))
        }
        try modelContext.save()
        return builtIn
    }

    func save(_ profiles: [ReadingProfile]) throws {
        let existing = try modelContext.fetch(FetchDescriptor<ReadingProfileRecord>())
        var byID: [UUID: ReadingProfileRecord] = [:]
        for record in existing { byID[record.id] = record }
        var keep = Set<UUID>()
        for (index, profile) in profiles.enumerated() {
            keep.insert(profile.id)
            if let record = byID[profile.id] {
                record.update(with: profile, sortIndex: index)
            } else {
                modelContext.insert(ReadingProfileRecord(profile: profile, sortIndex: index))
            }
        }
        for record in existing where !keep.contains(record.id) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    private func settingsRecord() throws -> SettingsRecord? {
        var descriptor = FetchDescriptor<SettingsRecord>(
            predicate: #Predicate { $0.id == "app" }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

final class SwiftDataSettingsRepository: SettingsRepository, @unchecked Sendable {

    private let store: SettingsDataStore

    init(store: SettingsDataStore) {
        self.store = store
    }

    func settings() async throws -> AppSettings { try await store.settings() }
    func save(_ settings: AppSettings) async throws { try await store.save(settings) }
    func readingProfiles() async throws -> [ReadingProfile] { try await store.readingProfiles() }
    func save(_ profiles: [ReadingProfile]) async throws { try await store.save(profiles) }
}
