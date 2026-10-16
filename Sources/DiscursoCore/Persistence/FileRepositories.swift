//
//  FileRepositories.swift
//  DiscursoCore
//
//  Implementações em arquivos dos contratos de persistência.
//
//  Cada discurso é um documento JSON independente (`speeches/<uuid>.json`).
//  Vantagens:
//   - gravar um discurso nunca reescreve os outros (sem corrupção em cascata);
//   - um arquivo corrompido afeta apenas um discurso, com recuperação por `.bak`;
//   - backup/restauração e sincronização futura ficam triviais (arquivo por
//     registro, com `updatedAt` para resolver conflitos).
//
//  A indexação local dos materiais usa um segundo arquivo por item
//  (`library/indexes/<uuid>.json`) para que a busca seja rápida e offline.
//

import Foundation

/// Repositório de discursos em arquivos JSON.
public actor FileSpeechRepository: SpeechRepository {

    private let store: DocumentStore
    private var warnings: [RepositoryWarning] = []
    /// Cache em memória dos discursos já carregados na sessão.
    private var cache: [UUID: Speech] = [:]

    public init(store: DocumentStore) {
        self.store = store
    }

    public init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.store = DocumentStore(baseDirectory: baseDirectory, fileManager: fileManager)
    }

    private func relativePath(for id: UUID) -> String {
        "\(DocumentPaths.speeches)/\(id.uuidString.lowercased()).json"
    }

    public func loadSummaries() async throws -> [SpeechSummary] {
        try await store.prepareDefaultLayout()
        let identifiers = store.listFileNames(in: DocumentPaths.speeches, extension: "json")
        var summaries: [SpeechSummary] = []
        for identifier in identifiers {
            guard let id = UUID(uuidString: identifier) else { continue }
            let speech = try await load(id: id)
            summaries.append(SpeechSummary(speech: speech))
        }
        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func loadAll() async throws -> [Speech] {
        try await store.prepareDefaultLayout()
        let identifiers = store.listFileNames(in: DocumentPaths.speeches, extension: "json")
        var speeches: [Speech] = []
        for identifier in identifiers {
            guard let id = UUID(uuidString: identifier) else { continue }
            speeches.append(try await load(id: id))
        }
        return speeches.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    public func load(id: UUID) async throws -> Speech {
        if let cached = cache[id] { return cached }
        guard let result = try await store.load(Speech.self, from: relativePath(for: id)) else {
            throw DocumentStoreError.notFound(relativePath(for: id))
        }
        var speech = result.value
        if let warning = result.warning {
            warnings.append(RepositoryWarning(message: warning))
        }
        // Garante que dados antigos ou adulterados estejam dentro das faixas.
        speech.presentation = speech.presentation.sanitized()
        speech.schemaVersion = max(speech.schemaVersion, 1)
        cache[id] = speech
        return speech
    }

    public func save(_ speech: Speech) async throws {
        var sanitized = speech
        sanitized.presentation = sanitized.presentation.sanitized()
        sanitized.schemaVersion = Speech.currentSchemaVersion
        try await store.save(sanitized, to: relativePath(for: sanitized.id))
        cache[sanitized.id] = sanitized
    }

    public func delete(id: UUID) async throws {
        cache.removeValue(forKey: id)
        try await store.delete(relativePath: relativePath(for: id))
    }

    public func folders() async throws -> [SpeechFolder] {
        guard let result = try await store.load([SpeechFolder].self, from: DocumentPaths.folderFileName) else {
            return []
        }
        if let warning = result.warning {
            warnings.append(RepositoryWarning(message: warning))
        }
        return result.value.sorted { $0.sortIndex < $1.sortIndex }
    }

    public func saveFolders(_ folders: [SpeechFolder]) async throws {
        try await store.save(folders, to: DocumentPaths.folderFileName)
    }

    public func takeWarnings() async -> [RepositoryWarning] {
        let current = warnings
        warnings.removeAll()
        return current
    }

    /// Diretório de dados usado (útil para backup e diagnóstico).
    public nonisolated var dataDirectory: URL { store.baseDirectory }
}

/// Repositório de materiais da biblioteca.
public actor FileLibraryRepository: LibraryRepository {

    private let store: DocumentStore
    private let fileManager: FileManager
    private var indexCache: [UUID: LibraryTextIndex] = [:]

    public init(store: DocumentStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    public init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.store = DocumentStore(baseDirectory: baseDirectory, fileManager: fileManager)
        self.fileManager = fileManager
    }

    private func relativePath(for id: UUID) -> String {
        "\(DocumentPaths.libraryItems)/\(id.uuidString.lowercased()).json"
    }

    public func loadItems() async throws -> [LibraryItem] {
        try await store.prepareDefaultLayout()
        let identifiers = store.listFileNames(in: DocumentPaths.libraryItems, extension: "json")
        var items: [LibraryItem] = []
        for identifier in identifiers {
            guard let id = UUID(uuidString: identifier),
                  let result = try? await store.load(LibraryItem.self, from: relativePath(for: id))
            else { continue }
            items.append(result.value)
        }
        return items.sorted { $0.importedAt > $1.importedAt }
    }

    public func load(id: UUID) async throws -> LibraryItem? {
        guard let result = try await store.load(LibraryItem.self, from: relativePath(for: id)) else {
            return nil
        }
        return result.value
    }

    public func save(_ item: LibraryItem) async throws {
        try await store.save(item, to: relativePath(for: item.id))
    }

    public func delete(id: UUID) async throws {
        if let item = try await load(id: id) {
            try? fileManager.removeItem(at: store.url(for: "\(DocumentPaths.libraryFiles)/\(item.fileName)"))
        }
        try? await deleteIndex(for: id)
        indexCache.removeValue(forKey: id)
        try await store.delete(relativePath: relativePath(for: id))
    }

    public func storeFile(from sourceURL: URL, itemID: UUID, fileExtension: String) async throws -> String {
        try await store.ensureDirectory(DocumentPaths.libraryFiles)
        let fileName = "\(itemID.uuidString.lowercased()).\(fileExtension.lowercased())"
        let destination = store.url(for: "\(DocumentPaths.libraryFiles)/\(fileName)")
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
        let path = store.url(for: "\(DocumentPaths.libraryFiles)/\(item.fileName)")
        return fileManager.fileExists(atPath: path.path) ? path : nil
    }

    public func saveIndex(_ index: LibraryTextIndex, for itemID: UUID) async throws {
        try await store.save(index, to: "\(DocumentPaths.libraryIndexes)/\(itemID.uuidString.lowercased()).json")
        indexCache[itemID] = index
    }

    public func loadIndex(for itemID: UUID) async throws -> LibraryTextIndex? {
        if let cached = indexCache[itemID] { return cached }
        guard let result = try await store.load(
            LibraryTextIndex.self,
            from: "\(DocumentPaths.libraryIndexes)/\(itemID.uuidString.lowercased()).json"
        ) else { return nil }
        indexCache[itemID] = result.value
        return result.value
    }

    public func deleteIndex(for itemID: UUID) async throws {
        indexCache.removeValue(forKey: itemID)
        try await store.delete(relativePath: "\(DocumentPaths.libraryIndexes)/\(itemID.uuidString.lowercased()).json")
    }

    /// Índices carregados em memória (usado pela busca local).
    public func cachedIndexes() -> [UUID: LibraryTextIndex] { indexCache }
}

/// Repositório de pesquisas salvas, histórico e cache.
public actor FileResearchRepository: ResearchRepository {

    private let store: DocumentStore

    public init(store: DocumentStore) {
        self.store = store
    }

    public init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.store = DocumentStore(baseDirectory: baseDirectory, fileManager: fileManager)
    }

    public func savedResearch() async throws -> [SavedResearch] {
        guard let result = try await store.load([SavedResearch].self, from: DocumentPaths.savedResearchFileName) else {
            return []
        }
        return result.value.sorted { $0.savedAt > $1.savedAt }
    }

    public func save(_ item: SavedResearch) async throws {
        var all = try await savedResearch()
        if let index = all.firstIndex(where: { $0.id == item.id }) {
            all[index] = item
        } else {
            all.insert(item, at: 0)
        }
        try await store.save(all, to: DocumentPaths.savedResearchFileName)
    }

    public func deleteSavedResearch(id: UUID) async throws {
        var all = try await savedResearch()
        all.removeAll { $0.id == id }
        try await store.save(all, to: DocumentPaths.savedResearchFileName)
    }

    public func searchHistory() async throws -> [SearchHistoryEntry] {
        guard let result = try await store.load([SearchHistoryEntry].self, from: DocumentPaths.searchHistoryFileName) else {
            return []
        }
        return result.value.sorted { $0.searchedAt > $1.searchedAt }
    }

    public func record(_ entry: SearchHistoryEntry) async throws {
        var all = try await searchHistory()
        // Evita repetir a mesma consulta consecutiva.
        if let first = all.first, PortugueseText.folded(first.query) == PortugueseText.folded(entry.query),
           first.failed == entry.failed {
            return
        }
        all.insert(entry, at: 0)
        if all.count > 100 { all = Array(all.prefix(100)) }
        try await store.save(all, to: DocumentPaths.searchHistoryFileName)
    }

    public func clearSearchHistory() async throws {
        try await store.delete(relativePath: DocumentPaths.searchHistoryFileName)
    }

    private func cacheFileName(forKey key: String) -> String {
        // Nome de arquivo seguro derivado da chave.
        let safe = PortugueseText.folded(key)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "\(DocumentPaths.researchCache)/\(safe.prefix(120)).json"
    }

    public func cachedResults(forKey key: String) async throws -> CachedResearchResults? {
        guard let result = try await store.load(CachedResearchResults.self, from: cacheFileName(forKey: key)) else {
            return nil
        }
        return result.value
    }

    public func cache(_ results: CachedResearchResults, forKey key: String) async throws {
        try await store.save(results, to: cacheFileName(forKey: key))
    }

    public func clearCache() async throws {
        let directory = store.url(for: DocumentPaths.researchCache)
        guard let contents = try? fileManagerContents(at: directory) else { return }
        for name in contents {
            try await store.delete(relativePath: "\(DocumentPaths.researchCache)/\(name)")
        }
    }

    private func fileManagerContents(at url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path)
    }
}

/// Repositório de configurações e perfis de leitura.
public actor FileSettingsRepository: SettingsRepository {

    private let store: DocumentStore

    public init(store: DocumentStore) {
        self.store = store
    }

    public init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.store = DocumentStore(baseDirectory: baseDirectory, fileManager: fileManager)
    }

    public func settings() async throws -> AppSettings {
        guard let result = try await store.load(AppSettings.self, from: DocumentPaths.appSettingsFileName) else {
            return .default
        }
        return result.value.sanitized()
    }

    public func save(_ settings: AppSettings) async throws {
        try await store.save(settings.sanitized(), to: DocumentPaths.appSettingsFileName)
    }

    public func readingProfiles() async throws -> [ReadingProfile] {
        guard let result = try await store.load([ReadingProfile].self, from: DocumentPaths.readingProfilesFileName) else {
            return ReadingProfile.builtInProfiles
        }
        let custom = result.value
        // Mantém os perfis prontos atualizados e acrescenta os do usuário.
        let builtInIDs = Set(ReadingProfile.builtInProfiles.map { $0.name })
        let userProfiles = custom.filter { !builtInIDs.contains($0.name) }
        return ReadingProfile.builtInProfiles + userProfiles
    }

    public func save(_ profiles: [ReadingProfile]) async throws {
        try await store.save(profiles, to: DocumentPaths.readingProfilesFileName)
    }
}
