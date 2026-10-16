//
//  LibraryViewModel.swift
//  DiscursoBiblico
//
//  Biblioteca pessoal: importação, categorias, favoritos, busca local
//  (offline) e situação da indexação.
//

import DiscursoCore
import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {

    private(set) var items: [LibraryItem] = []
    private(set) var indexes: [UUID: LibraryTextIndex] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var searchText = ""
    var selectedCategory: String?
    var selectedKind: LibraryItemKind?
    var showsFavoritesOnly = false

    // Importação
    private(set) var isImporting = false
    private(set) var lastReport: LibraryImportReport?

    private let repository: any LibraryRepository
    private let importer: LibraryImportService

    init(repository: any LibraryRepository, importer: LibraryImportService) {
        self.repository = repository
        self.importer = importer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await repository.loadItems()
            var indexes: [UUID: LibraryTextIndex] = [:]
            for item in items where item.indexStatus == .indexed {
                if let index = try? await repository.loadIndex(for: item.id) {
                    indexes[item.id] = index
                }
            }
            self.items = items
            self.indexes = indexes
            errorMessage = nil
        } catch {
            errorMessage = "Não foi possível carregar a biblioteca (\(error.localizedDescription))."
        }
    }

    // MARK: Filtros

    var categories: [String] {
        Array(Set(items.compactMap(\.category))).sorted()
    }

    var kinds: [LibraryItemKind] {
        Array(Set(items.map(\.kind))).sorted { $0.displayName < $1.displayName }
    }

    var filteredItems: [LibraryItem] {
        var result = items
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }
        if let selectedKind {
            result = result.filter { $0.kind == selectedKind }
        }
        if showsFavoritesOnly {
            result = result.filter(\.isFavorite)
        }
        let needle = PortugueseText.normalizedForSearch(searchText)
        if !needle.isEmpty {
            result = result.filter { item in
                PortugueseText.normalizedForSearch(item.displayTitle).contains(needle)
                    || (item.author.map { PortugueseText.normalizedForSearch($0).contains(needle) } ?? false)
                    || item.tags.contains { PortugueseText.normalizedForSearch($0).contains(needle) }
            }
        }
        return result.sorted { ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt) }
    }

    /// Resultados dentro do conteúdo dos materiais indexados (offline).
    var contentMatches: [LibrarySearchHit] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }
        return LibrarySearch.search(
            query: needle,
            items: filteredItems.isEmpty ? items : filteredItems,
            indexes: indexes,
            limit: 60
        )
    }

    var indexedCount: Int { items.filter { $0.indexStatus == .indexed }.count }
    var failedIndexCount: Int { items.filter { $0.indexStatus == .failed }.count }

    var totalSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: items.reduce(0) { $0 + $1.fileSize })
    }

    // MARK: Importação

    func importFiles(at urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        let report = await importer.importFiles(at: urls)
        lastReport = report
        await load()
    }

    func dismissReport() {
        lastReport = nil
    }

    func reindex(_ item: LibraryItem) async {
        _ = await importer.reindex(item)
        await load()
    }

    // MARK: Ações

    private func loadItem(id: UUID) async -> LibraryItem? {
        // `try?` sobre um retorno opcional cria um opcional duplo; o `?? nil`
        // simplifica para um único opcional.
        (try? await repository.load(id: id)) ?? nil
    }

    func toggleFavorite(_ item: LibraryItem) async {
        guard var copy = await loadItem(id: item.id) else { return }
        copy.isFavorite.toggle()
        try? await repository.save(copy)
        await load()
    }

    func setCategory(_ category: String?, for item: LibraryItem) async {
        guard var copy = await loadItem(id: item.id) else { return }
        copy.category = category?.isEmpty == true ? nil : category
        try? await repository.save(copy)
        await load()
    }

    func delete(_ item: LibraryItem) async {
        do {
            try await repository.delete(id: item.id)
            items.removeAll { $0.id == item.id }
            indexes[item.id] = nil
        } catch {
            errorMessage = "Não foi possível apagar (\(error.localizedDescription))."
        }
    }

    // A data de última abertura é gravada pelo leitor (ao abrir o material),
    // e não pela lista: um gesto sobre o `NavigationLink` chegava a impedir a
    // própria navegação da linha.

    func saveReadingPosition(_ item: LibraryItem, unitIndex: Int, fraction: Double, characterOffset: Int?) async {
        guard var copy = await loadItem(id: item.id) else { return }
        copy.lastReadPosition = LibraryReadingPosition(
            unitIndex: unitIndex,
            fractionInsideUnit: fraction,
            characterOffset: characterOffset
        )
        try? await repository.save(copy)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = copy
        }
    }

    func index(for item: LibraryItem) -> LibraryTextIndex? {
        indexes[item.id]
    }

    func categorySuggestions(for item: LibraryItem) -> [String] {
        var suggestions = categories
        if let kind = item.kind as LibraryItemKind? {
            let kindName = kind.displayName
            if !suggestions.contains(kindName) { suggestions.append(kindName) }
        }
        return suggestions
    }
}
