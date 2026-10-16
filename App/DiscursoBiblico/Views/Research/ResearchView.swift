//
//  ResearchView.swift
//  DiscursoBiblico
//
//  Pesquisa em fontes oficiais e na biblioteca local.
//
//  Regras que a tela reforça:
//   - uma consulta por vez, com intervalo mínimo e cache (política vinda das
//     configurações) — nada de raspagem em massa;
//   - quando a consulta direta não é possível, os **links oficiais** continuam
//     disponíveis para abrir no navegador;
//   - resultados podem ser salvos com nota e vinculados a um discurso.
//

import DiscursoCore
import SwiftUI
import UIKit

struct ResearchView: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var model: ResearchViewModel?
    @State private var section: SearchSection = .results
    @State private var savingResult: ResearchResult?
    @State private var noteDraft = ""
    @State private var attachingResult: ResearchResult?
    @State private var speechesForAttachment: [SpeechSummary] = []
    @State private var isLoadingSpeeches = false
    @State private var localPreviewItem: LibraryItem?

    /// Seções fixas da tela (nome próprio para não ofuscar `SwiftUI.Section`).
    enum SearchSection: String, CaseIterable, Identifiable {
        case results
        case saved
        case history

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .results: return "Resultados"
            case .saved: return "Salvos"
            case .history: return "Histórico"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView("Preparando a pesquisa…")
                }
            }
            .navigationTitle("Pesquisar")
            .toolbar { toolbar }
        }
        .task { await prepareModel() }
        .sheet(item: $localPreviewItem) { item in
            NavigationStack {
                LibraryReaderView(item: item)
            }
            .environment(environment)
        }
        .sheet(item: $savingResult) { result in
            NavigationStack {
                Form {
                    Section {
                        Text(result.displayTitle)
                            .font(.headline)
                        if let snippet = result.snippet {
                            Text(snippet)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        TextField("Nota pessoal (opcional)", text: $noteDraft, axis: .vertical)
                            .lineLimit(2...6)
                    } footer: {
                        Text("A fonte fica guardada neste aparelho, com o endereço e a data da consulta.")
                    }
                }
                .navigationTitle("Salvar fonte")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") {
                            noteDraft = ""
                            savingResult = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salvar") {
                            let note = noteDraft
                            noteDraft = ""
                            savingResult = nil
                            Task { await model?.save(result, note: note) }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $attachingResult) { result in
            NavigationStack {
                List {
                    if isLoadingSpeeches {
                        ProgressView("Carregando discursos…")
                    } else if speechesForAttachment.isEmpty {
                        ContentUnavailableView {
                            Label("Nenhum discurso", systemImage: "text.book.closed")
                        } description: {
                            Text("Crie um discurso para vincular esta fonte.")
                        }
                    } else {
                        ForEach(speechesForAttachment) { summary in
                            Button {
                                Task {
                                    await attach(result, to: summary)
                                    attachingResult = nil
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.displayTitle)
                                        .foregroundStyle(.primary)
                                    Text("\(summary.sectionCount) tópico(s)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Vincular a discurso")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { attachingResult = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func content(_ model: ResearchViewModel) -> some View {
        @Bindable var model = model

        List {
            searchSection(model)
            if section == .results {
                resultsSection(model)
            } else if section == .saved {
                savedSection(model)
            } else {
                historySection(model)
            }
            policyFooter
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $model.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Assunto, expressão ou referência (ex.: “João 3:16”)"
        )
        .onSubmit(of: .search) {
            Task { await model.search() }
        }
        .onChange(of: model.enabledProviderIDs) { _, ids in
            Task { await environment.saveSettings { $0.enabledResearchProviderIDs = ids } }
        }
        .refreshable {
            await model.search(forceRefresh: true)
        }
    }

    private func searchSection(_ model: ResearchViewModel) -> some View {
        Section {
            Picker("Seção", selection: $section) {
                ForEach(SearchSection.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)

            DisclosureGroup("Provedores de pesquisa") {
                ForEach(model.providers, id: \.id) { provider in
                    Toggle(isOn: Binding(
                        get: { model.enabledProviderIDs.contains(provider.id) },
                        set: { enabled in
                            var ids = model.enabledProviderIDs
                            if enabled {
                                if !ids.contains(provider.id) { ids.append(provider.id) }
                            } else {
                                ids.removeAll { $0 == provider.id }
                            }
                            model.enabledProviderIDs = ids
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                            if provider.requiresNetwork {
                                Text("Usa internet · respeita limites de uso")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            HStack {
                Menu {
                    Button("Todos os tipos") { model.selectedKind = nil }
                    ForEach(ResearchMaterialKind.allCases, id: \.self) { kind in
                        Button(kind.displayName) { model.selectedKind = kind }
                    }
                } label: {
                    IconTextLabel(
                        systemImage: "line.3.horizontal.decrease.circle",
                        text: model.selectedKind?.displayName ?? "Todos os tipos"
                    )
                }
                Spacer()
                Toggle("Só offline", isOn: Binding(
                    get: { model.showsOnlyLocal },
                    set: { model.showsOnlyLocal = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                Text("Só offline")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message = model.statusMessage {
                MessageBanner(kind: statusKind(model.outcome.status), message: message)
            }

            if model.isSearching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Consultando as fontes…")
                        .font(.footnote)
                }
            }

            if !model.providerErrorMessages.isEmpty {
                DisclosureGroup("Falhas em provedores") {
                    ForEach(model.providerErrorMessages, id: \.provider) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.provider)
                                .font(.footnote.weight(.semibold))
                            Text(item.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultsSection(_ model: ResearchViewModel) -> some View {
        let results = model.filteredResults
        if model.outcome.status == .idle {
            Section {
                ContentUnavailableView {
                    Label("Pesquise uma fonte", systemImage: "magnifyingglass")
                } description: {
                    Text("Digite um assunto ou uma referência e toque em Buscar. A pesquisa respeita os limites de uso das fontes oficiais e guarda resultados em cache.")
                }
            }
        } else if !results.isEmpty {
            Section {
                ForEach(results) { result in
                    resultRow(model, result: result)
                }
            } header: {
                HStack {
                    Text("\(results.count) resultado(s)")
                    if !model.outcome.cachedProviderIDs.isEmpty {
                        Spacer()
                        Text("inclui resultados guardados")
                            .font(.caption2)
                    }
                }
            }
        }

        Section {
            if let searchURL = officialSearchURL(query: model.outcome.query.isEmpty ? model.query : model.outcome.query) {
                Button {
                    UIApplication.shared.open(searchURL)
                } label: {
                    IconTextLabel(systemImage: "safari", text: "Pesquisar no site oficial (wol.jw.org)")
                }
            }
        } header: {
            Text("Consulta direta no site oficial")
        } footer: {
            Text("Sempre disponível: abre a pesquisa oficial no navegador, sem depender da consulta automática.")
        }
    }

    private func resultRow(_ model: ResearchViewModel, result: ResearchResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: result.kind.systemImageName)
                    .foregroundStyle(.tint)
                Text(result.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                if result.isAvailableOffline {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Disponível offline")
                }
            }

            if let publication = result.publication, !publication.isEmpty {
                Text(publication)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let snippet = result.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 14) {
                if result.url != nil || result.libraryItemID != nil {
                    Button {
                        Task { await openResult(result) }
                    } label: {
                        Label(result.libraryItemID != nil ? "Ler aqui" : "Abrir", systemImage: result.libraryItemID != nil ? "book" : "safari")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }

                if result.libraryItemID != nil {
                    Label("Na biblioteca", systemImage: "books.vertical")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    noteDraft = ""
                    savingResult = result
                } label: {
                    Label(model.isSaved(result) ? "Salvo" : "Salvar", systemImage: model.isSaved(result) ? "checkmark.circle" : "bookmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(model.isSaved(result))

                Button {
                    Task { await prepareAttachment(for: result) }
                } label: {
                    Label("Vincular", systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(result.accessedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func savedSection(_ model: ResearchViewModel) -> some View {
        if model.saved.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Nenhuma fonte salva", systemImage: "bookmark")
                } description: {
                    Text("Ao salvar um resultado, ele fica aqui com sua nota — inclusive sem internet.")
                }
            }
        } else {
            Section {
                ForEach(model.saved) { item in
                    SavedResearchRow(
                        item: item,
                        onUpdateNote: { note in
                            Task { await model.updateNote(note, savedID: item.id) }
                        },
                        onOpen: {
                            Task {
                                if let itemID = item.result.libraryItemID,
                                   let localItem = (try? await environment.libraryRepository.load(id: itemID)) ?? nil {
                                    localPreviewItem = localItem
                                } else if let url = item.result.url {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await model.removeSaved(id: item.id) }
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("\(model.saved.count) fonte(s) salva(s)")
            } footer: {
                Text("As fontes salvas podem ser vinculadas a discursos (botão “Vincular” nos resultados).")
            }
        }
    }

    @ViewBuilder
    private func historySection(_ model: ResearchViewModel) -> some View {
        if model.history.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Histórico vazio", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("As pesquisas feitas aparecem aqui para repetir com um toque.")
                }
            }
        } else {
            Section {
                ForEach(model.history) { entry in
                    Button {
                        section = .results
                        Task { await model.repeatSearch(entry.query) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.query)
                                .foregroundStyle(.primary)
                            Text(
                                "\(entry.resultCount) resultado(s) · \(entry.searchedAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(entry.failed && entry.resultCount == 0)
                }
            } header: {
                Text("Últimas pesquisas")
            }
        }
    }

    private var policyFooter: some View {
        Section {
            Text("A consulta automática usa um pedido por vez, com intervalo mínimo e cache — configurações em Ajustes › Pesquisa. Nenhuma página é baixada em massa.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Barra de ferramentas

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model?.search() }
            } label: {
                if model?.isSearching == true {
                    ProgressView()
                } else {
                    Image(systemName: "magnifyingglass")
                }
            }
            .disabled(model?.isSearching == true || (model?.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
            .accessibilityLabel("Buscar")
        }
    }

    // MARK: Ações

    private func prepareModel() async {
        if model == nil {
            model = ResearchViewModel(
                service: environment.research,
                repository: environment.researchRepository
            )
        }
        await model?.load()
        if let model, model.enabledProviderIDs != environment.settings.enabledResearchProviderIDs {
            model.enabledProviderIDs = environment.settings.enabledResearchProviderIDs
        }
    }

    private func openResult(_ result: ResearchResult) async {
        if let itemID = result.libraryItemID,
           let item = (try? await environment.libraryRepository.load(id: itemID)) ?? nil {
            localPreviewItem = item
            return
        }
        if let url = result.url {
            UIApplication.shared.open(url)
        }
    }

    private func prepareAttachment(for result: ResearchResult) async {
        attachingResult = result
        isLoadingSpeeches = true
        defer { isLoadingSpeeches = false }
        speechesForAttachment = (try? await environment.speechRepository.loadSummaries()) ?? []
    }

    private func attach(_ result: ResearchResult, to summary: SpeechSummary) async {
        guard var speech = try? await environment.speechRepository.load(id: summary.id) else { return }
        let source = result.asSourceLink()
        guard !speech.sources.contains(where: { $0.url == source.url && $0.title == source.title }) else { return }
        speech.sources.append(source)
        speech.updatedAt = Date()
        try? await environment.speechRepository.save(speech)
        Haptics.success()
    }

    private func officialSearchURL(query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://wol.jw.org/pt/wol/s/r5/lp-t")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "p", value: "par")
        ]
        return components?.url
    }

    private func statusKind(_ status: ResearchStatus) -> MessageBanner.Kind {
        switch status {
        case .offline: return .warning
        case .failed: return .error
        default: return .info
        }
    }
}

// MARK: - Linha de fonte salva

private struct SavedResearchRow: View {

    let item: SavedResearch
    let onUpdateNote: (String) -> Void
    let onOpen: () -> Void

    @State private var isEditingNote = false
    @State private var noteDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.result.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(item.savedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let publication = item.result.publication {
                Text(publication)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.note.isEmpty {
                Button {
                    noteDraft = ""
                    isEditingNote = true
                } label: {
                    Label("Adicionar nota", systemImage: "note.text.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            } else {
                Text(item.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 14) {
                if item.result.url != nil || item.result.libraryItemID != nil {
                    Button {
                        onOpen()
                    } label: {
                        Label(item.result.libraryItemID != nil ? "Ler aqui" : "Abrir", systemImage: item.result.libraryItemID != nil ? "book" : "safari")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    noteDraft = item.note
                    isEditingNote = true
                } label: {
                    Label("Editar nota", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 3)
        .alert("Nota da fonte", isPresented: $isEditingNote) {
            TextField("Nota", text: $noteDraft, axis: .vertical)
            Button("Salvar") {
                onUpdateNote(noteDraft)
                noteDraft = ""
            }
            Button("Cancelar", role: .cancel) { noteDraft = "" }
        }
    }
}

#Preview {
    ResearchView()
        .environment(AppEnvironment.preview())
}
