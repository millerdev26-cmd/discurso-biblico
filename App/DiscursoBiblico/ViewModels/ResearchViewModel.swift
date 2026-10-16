//
//  ResearchViewModel.swift
//  DiscursoBiblico
//
//  Pesquisa: consulta o `ResearchService` do núcleo e apresenta o resultado
//  de forma clara — incluindo "sem conexão", "bloqueado" e "nada encontrado".
//
//  Regras que a interface reforça:
//   - nenhuma página é raspada em massa; a consulta é uma por vez, com
//     intervalo mínimo (a política vem das configurações);
//   - quando a consulta direta não é possível, os **links oficiais** continuam
//     disponíveis;
//   - resultados podem ser salvos com nota e vinculados ao discurso.
//

import DiscursoCore
import Foundation
import Observation

@MainActor
@Observable
final class ResearchViewModel {

    var query = ""
    private(set) var outcome = ResearchSearchOutcome(query: "", status: .idle)
    private(set) var isSearching = false

    private(set) var saved: [SavedResearch] = []
    private(set) var history: [SearchHistoryEntry] = []
    private(set) var providers: [(id: String, displayName: String, requiresNetwork: Bool)] = []

    var enabledProviderIDs: [String] = ResearchProviderID.allDefaults
    var selectedKind: ResearchMaterialKind?
    var showsOnlyLocal = false

    private let service: ResearchService
    private let repository: any ResearchRepository

    init(service: ResearchService, repository: any ResearchRepository) {
        self.service = service
        self.repository = repository
    }

    func load() async {
        providers = await service.availableProviders()
        saved = (try? await repository.savedResearch()) ?? []
        history = (try? await repository.searchHistory()) ?? []
    }

    // MARK: Pesquisa

    func search(forceRefresh: Bool = false) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            outcome = ResearchSearchOutcome(query: "", status: .empty)
            return
        }
        isSearching = true
        outcome = ResearchSearchOutcome(query: trimmed, status: .loading)
        defer { isSearching = false }

        let result = await service.search(
            trimmed,
            enabledProviderIDs: enabledProviderIDs,
            forceRefresh: forceRefresh
        )
        outcome = result
        history = (try? await repository.searchHistory()) ?? []
    }

    func repeatSearch(_ text: String) async {
        query = text
        await search()
    }

    func clearOutcome() {
        outcome = ResearchSearchOutcome(query: "", status: .idle)
    }

    // MARK: Resultados

    var filteredResults: [ResearchResult] {
        var results = outcome.results
        if let selectedKind {
            results = results.filter { $0.kind == selectedKind }
        }
        if showsOnlyLocal {
            results = results.filter { $0.isAvailableOffline }
        }
        return results
    }

    var statusMessage: String? {
        switch outcome.status {
        case .idle, .success, .loading:
            return nil
        case .empty:
            return "Nada encontrado. Tente outras palavras, uma referência (ex.: “João 3:16”) ou use os links oficiais."
        case .offline:
            return "Sem conexão: a pesquisa local continua disponível e os links oficiais podem ser abertos no navegador."
        case .failed(let reason):
            return reason
        }
    }

    var providerErrorMessages: [(provider: String, message: String)] {
        outcome.providerErrors.compactMap { key, value in
            let name = providers.first { $0.id == key }?.displayName ?? key
            return (name, value)
        }.sorted { $0.provider < $1.provider }
    }

    func isSaved(_ result: ResearchResult) -> Bool {
        guard let url = result.url?.absoluteString else { return false }
        return saved.contains { $0.result.urlString == url }
    }

    // MARK: Salvar

    func save(_ result: ResearchResult, note: String = "") async {
        let item = SavedResearch(
            query: outcome.query.isEmpty ? result.title : outcome.query,
            result: ResearchResultPayload(result: result),
            note: note
        )
        try? await repository.save(item)
        saved = (try? await repository.savedResearch()) ?? []
    }

    func removeSaved(id: UUID) async {
        try? await repository.deleteSavedResearch(id: id)
        saved = (try? await repository.savedResearch()) ?? []
    }

    func updateNote(_ note: String, savedID: UUID) async {
        guard var item = saved.first(where: { $0.id == savedID }) else { return }
        item.note = note
        try? await repository.save(item)
        saved = (try? await repository.savedResearch()) ?? []
    }

    func clearHistory() async {
        try? await repository.clearSearchHistory()
        history = []
    }

    func clearCache() async {
        try? await repository.clearCache()
    }
}
