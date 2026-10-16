//
//  SpeechListViewModel.swift
//  DiscursoBiblico
//
//  Lista de discursos: busca, pastas, favoritos, ordenação e atalho
//  "continuar de onde parei".
//

import DiscursoCore
import Foundation
import Observation

@MainActor
@Observable
final class SpeechListViewModel {

    private(set) var summaries: [SpeechSummary] = []
    private(set) var folders: [SpeechFolder] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var searchText = ""
    var selectedFolderID: UUID?
    var showsFavoritesOnly = false
    var sortOption: SpeechSortOption = .recentlyUpdated

    private let repository: any SpeechRepository

    init(repository: any SpeechRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let summaries = try await repository.loadSummaries()
            let folders = try await repository.folders()
            self.summaries = summaries
            self.folders = folders
            errorMessage = nil
        } catch {
            errorMessage = "Não foi possível carregar os discursos (\(error.localizedDescription))."
        }
    }

    // MARK: Filtros

    var filteredSummaries: [SpeechSummary] {
        var result = summaries

        if let selectedFolderID {
            result = result.filter { $0.folderID == selectedFolderID }
        }
        if showsFavoritesOnly {
            result = result.filter(\.isFavorite)
        }
        let needle = PortugueseText.normalizedForSearch(searchText)
        if !needle.isEmpty {
            result = result.filter { summary in
                PortugueseText.normalizedForSearch(summary.title).contains(needle)
                    || PortugueseText.normalizedForSearch(summary.subtitle).contains(needle)
                    || PortugueseText.normalizedForSearch(summary.occasion).contains(needle)
                    || summary.tags.contains { PortugueseText.normalizedForSearch($0).contains(needle) }
            }
        }
        return sorted(result)
    }

    private func sorted(_ list: [SpeechSummary]) -> [SpeechSummary] {
        switch sortOption {
        case .recentlyUpdated:
            return list.sorted { $0.updatedAt > $1.updatedAt }
        case .recentlyCreated:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .plannedDuration:
            return list.sorted { $0.displayMinutes > $1.displayMinutes }
        case .preparation:
            return list.sorted { $0.preparationProgress > $1.preparationProgress }
        }
    }

    var favoriteCount: Int { summaries.filter(\.isFavorite).count }

    /// Último discurso aberto (para o botão "Continuar").
    func continueTarget(lastOpenedID: UUID?) -> SpeechSummary? {
        if let lastOpenedID, let match = summaries.first(where: { $0.id == lastOpenedID }) {
            return match
        }
        return summaries.max { $0.updatedAt < $1.updatedAt }
    }

    // MARK: Ações

    func delete(_ summary: SpeechSummary) async {
        do {
            try await repository.delete(id: summary.id)
            summaries.removeAll { $0.id == summary.id }
        } catch {
            errorMessage = "Não foi possível apagar (\(error.localizedDescription))."
        }
    }

    @discardableResult
    func duplicate(_ summary: SpeechSummary) async -> Speech? {
        guard let original = try? await repository.load(id: summary.id) else { return nil }
        let copy = original.duplicated()
        do {
            try await repository.save(copy)
            await load()
            return copy
        } catch {
            errorMessage = "Não foi possível duplicar (\(error.localizedDescription))."
            return nil
        }
    }

    func toggleFavorite(_ summary: SpeechSummary) async {
        guard var speech = try? await repository.load(id: summary.id) else { return }
        speech.isFavorite.toggle()
        speech.updatedAt = Date()
        try? await repository.save(speech)
        await load()
    }

    func move(_ summary: SpeechSummary, toFolder folderID: UUID?) async {
        guard var speech = try? await repository.load(id: summary.id) else { return }
        speech.folderID = folderID
        speech.updatedAt = Date()
        try? await repository.save(speech)
        await load()
    }

    func createSpeech(
        title: String = "Novo discurso",
        folderID: UUID? = nil,
        template: SpeechTemplate = .blank
    ) async -> Speech? {
        var speech = template.makeSpeech(title: title)
        speech.folderID = folderID
        do {
            try await repository.save(speech)
            await load()
            return speech
        } catch {
            errorMessage = "Não foi possível criar o discurso (\(error.localizedDescription))."
            return nil
        }
    }

    func createFolder(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var folders = try? await repository.folders()
        folders = (folders ?? []) + [SpeechFolder(name: trimmed, sortIndex: (folders?.count ?? 0))]
        try? await repository.saveFolders(folders ?? [])
        await load()
    }

    func renameFolder(_ folder: SpeechFolder, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var folders = (try? await repository.folders()) ?? []
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].name = trimmed
        folders[index].updatedAt = Date()
        try? await repository.saveFolders(folders)
        await load()
    }

    func deleteFolder(_ folder: SpeechFolder) async {
        var folders = (try? await repository.folders()) ?? []
        folders.removeAll { $0.id == folder.id }
        try? await repository.saveFolders(folders)

        // Discursos da pasta voltam para "sem pasta" (nunca são apagados).
        for summary in summaries where summary.folderID == folder.id {
            await move(summary, toFolder: nil)
        }
        await load()
    }
}

// MARK: - Modelos de discurso

/// Estruturas iniciais sugeridas (o usuário edita tudo).
enum SpeechTemplate: String, CaseIterable, Identifiable {
    case blank
    case talk
    case bibleStudy
    
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: return "Em branco"
        case .talk: return "Discurso (introdução, corpo, conclusão)"
        case .bibleStudy: return "Estudo bíblico"
        }
    }

    func makeSpeech(title: String, now: Date = Date()) -> Speech {
        switch self {
        case .blank:
            return Speech(title: title, sections: [Self.section("Tópico 1")])
        case .talk:
            return Speech(
                title: title,
                sections: [
                    Self.section("Introdução"),
                    Self.section("Desenvolvimento 1"),
                    Self.section("Desenvolvimento 2"),
                    Self.section("Conclusão")
                ]
            )
        case .bibleStudy:
            return Speech(
                title: title,
                sections: [
                    Self.section("Introdução"),
                    Self.section("Texto principal"),
                    Self.section("Aplicação"),
                    Self.section("Revisão")
                ]
            )
        }
    }

    private static func section(_ title: String) -> SpeechSection {
        SpeechSection(
            title: title,
            blocks: [
                .heading(title),
                .paragraph("")
            ]
        )
    }
}
