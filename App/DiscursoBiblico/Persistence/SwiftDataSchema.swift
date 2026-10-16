//
//  SwiftDataSchema.swift
//  DiscursoBiblico
//
//  Registros do SwiftData.
//
//  Estratégia: cada registro guarda (a) colunas de índice usadas pelas listas
//  e buscas — título, datas, contagens, favorito, categoria — e (b) o modelo
//  completo do núcleo codificado em JSON (`payload`). Isso mantém **uma única
//  fonte de verdade** para o formato dos dados (os modelos do `DiscursoCore`,
//  já testados) sem perder a consulta rápida do SwiftData.
//
//  Arquivos da biblioteca (EPUB/PDF/TXT/…) ficam em disco, na pasta de suporte
//  do aplicativo, e são gerenciados por `LibraryFileStore`.
//

import DiscursoCore
import Foundation
import SwiftData

// MARK: - Discursos

@Model
final class SpeechRecord {

    @Attribute(.unique) var id: UUID
    var title: String
    var subtitle: String
    var occasion: String
    var folderID: UUID?
    var statusRaw: String
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var plannedMinutes: Double?
    var sectionCount: Int
    var wordCount: Int
    var estimatedMinutes: Double
    var referenceCount: Int
    var sourceCount: Int
    var preparationProgress: Double
    var lastReadSectionTitle: String?
    var lastReadFraction: Double?

    /// Modelo completo (`Speech`) codificado.
    @Attribute(.externalStorage) var payload: Data

    init(speech: Speech) {
        self.id = speech.id
        self.title = speech.displayTitle
        self.subtitle = speech.subtitle
        self.occasion = speech.occasion
        self.folderID = speech.folderID
        self.statusRaw = speech.status.rawValue
        self.isFavorite = speech.isFavorite
        self.createdAt = speech.createdAt
        self.updatedAt = speech.updatedAt
        self.payload = PayloadCoding.encode(speech)
        self.applyIndexColumns(speech)
    }

    /// Atualiza as colunas de índice a partir do modelo.
    func applyIndexColumns(_ speech: Speech) {
        let summary = SpeechSummary(speech: speech)
        title = summary.title
        subtitle = summary.subtitle
        occasion = summary.occasion
        folderID = summary.folderID
        statusRaw = summary.status.rawValue
        isFavorite = summary.isFavorite
        plannedMinutes = summary.plannedMinutes
        sectionCount = summary.sectionCount
        wordCount = summary.wordCount
        estimatedMinutes = summary.estimatedMinutes
        referenceCount = summary.referenceCount
        sourceCount = summary.sourceCount
        preparationProgress = summary.preparationProgress
        lastReadSectionTitle = summary.lastReadSectionTitle
        lastReadFraction = summary.lastReadFraction
        updatedAt = summary.updatedAt
    }

    func update(with speech: Speech) {
        payload = PayloadCoding.encode(speech)
        applyIndexColumns(speech)
        createdAt = speech.createdAt
    }

    var speech: Speech? { PayloadCoding.decode(Speech.self, from: payload) }

    var summary: SpeechSummary {
        SpeechSummary(
            id: id,
            title: title,
            subtitle: subtitle,
            occasion: occasion,
            tags: speech?.tags ?? [],
            folderID: folderID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: SpeechStatus(rawValue: statusRaw) ?? .preparing,
            isFavorite: isFavorite,
            sectionCount: sectionCount,
            wordCount: wordCount,
            estimatedMinutes: estimatedMinutes,
            plannedMinutes: plannedMinutes,
            referenceCount: referenceCount,
            sourceCount: sourceCount,
            preparationProgress: preparationProgress,
            lastReadSectionTitle: lastReadSectionTitle,
            lastReadFraction: lastReadFraction
        )
    }
}

@Model
final class SpeechFolderRecord {

    @Attribute(.unique) var id: UUID
    var name: String
    var parentID: UUID?
    var sortIndex: Int
    var updatedAt: Date
    var payload: Data

    init(folder: SpeechFolder) {
        self.id = folder.id
        self.name = folder.name
        self.parentID = folder.parentID
        self.sortIndex = folder.sortIndex
        self.updatedAt = folder.updatedAt
        self.payload = PayloadCoding.encode(folder)
    }

    func update(with folder: SpeechFolder) {
        name = folder.name
        parentID = folder.parentID
        sortIndex = folder.sortIndex
        updatedAt = folder.updatedAt
        payload = PayloadCoding.encode(folder)
    }

    var folder: SpeechFolder? { PayloadCoding.decode(SpeechFolder.self, from: payload) }
}

// MARK: - Biblioteca

@Model
final class LibraryItemRecord {

    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String
    var category: String?
    var isFavorite: Bool
    var importedAt: Date
    var lastOpenedAt: Date?
    var indexStatusRaw: String
    var fileSize: Int64
    @Attribute(.externalStorage) var payload: Data

    init(item: LibraryItem) {
        self.id = item.id
        self.title = item.displayTitle
        self.kindRaw = item.kind.rawValue
        self.category = item.category
        self.isFavorite = item.isFavorite
        self.importedAt = item.importedAt
        self.lastOpenedAt = item.lastOpenedAt
        self.indexStatusRaw = item.indexStatus.rawValue
        self.fileSize = item.fileSize
        self.payload = PayloadCoding.encode(item)
    }

    func update(with item: LibraryItem) {
        title = item.displayTitle
        kindRaw = item.kind.rawValue
        category = item.category
        isFavorite = item.isFavorite
        importedAt = item.importedAt
        lastOpenedAt = item.lastOpenedAt
        indexStatusRaw = item.indexStatus.rawValue
        fileSize = item.fileSize
        payload = PayloadCoding.encode(item)
    }

    var item: LibraryItem? { PayloadCoding.decode(LibraryItem.self, from: payload) }
}

@Model
final class LibraryIndexRecord {

    @Attribute(.unique) var itemID: UUID
    var builtAt: Date
    @Attribute(.externalStorage) var payload: Data

    init(index: LibraryTextIndex) {
        self.itemID = index.itemID
        self.builtAt = index.builtAt
        self.payload = PayloadCoding.encode(index)
    }

    func update(with index: LibraryTextIndex) {
        builtAt = index.builtAt
        payload = PayloadCoding.encode(index)
    }

    var index: LibraryTextIndex? { PayloadCoding.decode(LibraryTextIndex.self, from: payload) }
}

// MARK: - Pesquisa

@Model
final class SavedResearchRecord {

    @Attribute(.unique) var id: UUID
    var query: String
    var title: String
    var kindRaw: String
    var savedAt: Date
    var payload: Data

    init(saved: SavedResearch) {
        self.id = saved.id
        self.query = saved.query
        self.title = saved.result.title
        self.kindRaw = saved.result.kind.rawValue
        self.savedAt = saved.savedAt
        self.payload = PayloadCoding.encode(saved)
    }

    func update(with saved: SavedResearch) {
        query = saved.query
        title = saved.result.title
        kindRaw = saved.result.kind.rawValue
        savedAt = saved.savedAt
        payload = PayloadCoding.encode(saved)
    }

    var saved: SavedResearch? { PayloadCoding.decode(SavedResearch.self, from: payload) }
}

@Model
final class SearchHistoryRecord {

    @Attribute(.unique) var id: UUID
    var query: String
    var searchedAt: Date
    var failed: Bool
    var resultCount: Int
    var payload: Data

    init(entry: SearchHistoryEntry) {
        self.id = entry.id
        self.query = entry.query
        self.searchedAt = entry.searchedAt
        self.failed = entry.failed
        self.resultCount = entry.resultCount
        self.payload = PayloadCoding.encode(entry)
    }

    var entry: SearchHistoryEntry? { PayloadCoding.decode(SearchHistoryEntry.self, from: payload) }
}

@Model
final class CachedResearchRecord {

    @Attribute(.unique) var key: String
    var query: String
    var providerID: String
    var storedAt: Date
    var payload: Data

    init(key: String, cached: CachedResearchResults) {
        self.key = key
        self.query = cached.query
        self.providerID = cached.providerID
        self.storedAt = cached.storedAt
        self.payload = PayloadCoding.encode(cached)
    }

    func update(with cached: CachedResearchResults) {
        query = cached.query
        providerID = cached.providerID
        storedAt = cached.storedAt
        payload = PayloadCoding.encode(cached)
    }

    var cached: CachedResearchResults? { PayloadCoding.decode(CachedResearchResults.self, from: payload) }
}

// MARK: - Configurações

@Model
final class SettingsRecord {

    /// Registro único: `id` fixo "app".
    @Attribute(.unique) var id: String
    var updatedAt: Date
    var payload: Data

    init(settings: AppSettings) {
        self.id = "app"
        self.updatedAt = Date()
        self.payload = PayloadCoding.encode(settings)
    }

    func update(with settings: AppSettings) {
        updatedAt = Date()
        payload = PayloadCoding.encode(settings)
    }

    var settings: AppSettings? { PayloadCoding.decode(AppSettings.self, from: payload) }
}

@Model
final class ReadingProfileRecord {

    @Attribute(.unique) var id: UUID
    var name: String
    var isBuiltIn: Bool
    var sortIndex: Int
    var payload: Data

    init(profile: ReadingProfile, sortIndex: Int = 0) {
        self.id = profile.id
        self.name = profile.name
        self.isBuiltIn = profile.isBuiltIn
        self.sortIndex = sortIndex
        self.payload = PayloadCoding.encode(profile)
    }

    func update(with profile: ReadingProfile, sortIndex: Int? = nil) {
        name = profile.name
        isBuiltIn = profile.isBuiltIn
        if let sortIndex { self.sortIndex = sortIndex }
        payload = PayloadCoding.encode(profile)
    }

    var profile: ReadingProfile? { PayloadCoding.decode(ReadingProfile.self, from: payload) }
}
