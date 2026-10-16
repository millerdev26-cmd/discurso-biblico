//
//  SpeechListView.swift
//  DiscursoBiblico
//
//  Lista de discursos: busca, pastas, favoritos, ordenação e o atalho
//  "Continuar de onde parei".
//
//  A tela nunca esconde ações importantes atrás de gestos difíceis: tudo tem
//  botão de menu, contexto e acessibilidade.
//

import DiscursoCore
import SwiftUI

struct SpeechListView: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var model: SpeechListViewModel?

    @State private var isFolderAlertPresented = false
    @State private var folderNameDraft = ""
    @State private var renamedFolder: SpeechFolder?
    @State private var speechPendingDeletion: SpeechSummary?
    @State private var speechPendingMove: SpeechSummary?
    @State private var isSortMenuPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView("Carregando discursos…")
                }
            }
            .navigationTitle("Discursos")
            .toolbar { toolbar }
        }
        .task { await prepareModel() }
        .onAppear {
            // Ao voltar do editor/detalhe a lista recarrega para refletir
            // títulos, progresso e situação atualizados.
            if model != nil {
                Task { await model?.load() }
            }
        }
        .alert("Nova pasta", isPresented: $isFolderAlertPresented) {
            TextField("Nome da pasta", text: $folderNameDraft)
            Button("Criar") {
                let name = folderNameDraft
                folderNameDraft = ""
                Task { await model?.createFolder(named: name) }
            }
            Button("Cancelar", role: .cancel) { folderNameDraft = "" }
        } message: {
            Text("Pastas ajudam a separar discursos por ocasião ou série.")
        }
        .alert(
            "Renomear pasta",
            isPresented: Binding(
                get: { renamedFolder != nil },
                set: { if !$0 { renamedFolder = nil } }
            )
        ) {
            TextField("Nome da pasta", text: $folderNameDraft)
            Button("Salvar") {
                if let folder = renamedFolder {
                    let name = folderNameDraft
                    Task { await model?.renameFolder(folder, to: name) }
                }
                renamedFolder = nil
                folderNameDraft = ""
            }
            Button("Cancelar", role: .cancel) {
                renamedFolder = nil
                folderNameDraft = ""
            }
        }
        .confirmationDialog(
            speechPendingMove.map { "Mover “\($0.displayTitle)”" } ?? "Mover discurso",
            isPresented: Binding(
                get: { speechPendingMove != nil },
                set: { if !$0 { speechPendingMove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sem pasta") {
                if let speech = speechPendingMove {
                    Task { await model?.move(speech, toFolder: nil) }
                }
                speechPendingMove = nil
            }
            ForEach(model?.folders ?? []) { folder in
                Button(folder.name) {
                    if let speech = speechPendingMove {
                        Task { await model?.move(speech, toFolder: folder.id) }
                    }
                    speechPendingMove = nil
                }
            }
            Button("Cancelar", role: .cancel) { speechPendingMove = nil }
        }
        .alert(
            "Apagar discurso?",
            isPresented: Binding(
                get: { speechPendingDeletion != nil },
                set: { if !$0 { speechPendingDeletion = nil } }
            ),
            presenting: speechPendingDeletion
        ) { speech in
            Button("Apagar", role: .destructive) {
                Task { await model?.delete(speech) }
                speechPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) { speechPendingDeletion = nil }
        } message: { speech in
            Text("“\(speech.displayTitle)” será apagado do aparelho. Esta ação não pode ser desfeita.")
        }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func content(_ model: SpeechListViewModel) -> some View {
        @Bindable var model = model

        List {
            if let message = model.errorMessage {
                MessageBanner(kind: .error, message: message)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            if let target = model.continueTarget(lastOpenedID: environment.settings.lastOpenedSpeechID) {
                continueSection(target)
            }

            foldersSection(model)
            listSection(model)
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $model.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Buscar por título, ocasião ou etiqueta"
        )
        .refreshable { await model.load() }
        .overlay {
            if model.summaries.isEmpty, !model.isLoading {
                EmptyStateView(
                    title: "Nenhum discurso ainda",
                    message: "Crie o primeiro discurso para começar a preparar. Tudo fica guardado neste aparelho.",
                    systemImage: "text.book.closed",
                    actionTitle: "Criar discurso"
                ) {
                    createSpeech(.talk)
                }
            } else if model.filteredSummaries.isEmpty, !model.summaries.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
    }

    private func continueSection(_ target: SpeechSummary) -> some View {
        Section {
            // Sem gestos adicionais: um `simultaneousGesture` sobre o
            // `NavigationLink` chega a impedir a navegação no iOS (o toque
            // registra o efeito colateral, mas a tela não abre). O registro
            // de "último discurso aberto" acontece na tela de detalhe.
            NavigationLink {
                SpeechDetailView(speechID: target.id, startsInPresentation: true)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Continuar: \(target.displayTitle)")
                            .font(.headline)
                            .lineLimit(1)
                        if let section = target.lastReadSectionTitle, !section.isEmpty {
                            Text("Retomar em “\(section)”")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            DurationText(minutes: target.displayMinutes, prefix: "≈")
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func foldersSection(_ model: SpeechListViewModel) -> some View {
        if !model.folders.isEmpty || model.favoriteCount > 0 {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        filterChip(
                            title: "Todos",
                            systemImage: "tray.full",
                            isSelected: model.selectedFolderID == nil && !model.showsFavoritesOnly
                        ) {
                            model.selectedFolderID = nil
                            model.showsFavoritesOnly = false
                        }
                        filterChip(
                            title: "Favoritos (\(model.favoriteCount))",
                            systemImage: "star.fill",
                            isSelected: model.showsFavoritesOnly
                        ) {
                            model.showsFavoritesOnly.toggle()
                        }
                    }

                    if !model.folders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(model.folders) { folder in
                                    filterChip(
                                        title: folder.name,
                                        systemImage: "folder",
                                        isSelected: model.selectedFolderID == folder.id
                                    ) {
                                        model.selectedFolderID =
                                            model.selectedFolderID == folder.id ? nil : folder.id
                                    }
                                    .contextMenu {
                                        Button {
                                            folderNameDraft = folder.name
                                            renamedFolder = folder
                                        } label: {
                                            Label("Renomear pasta", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            Task { await model.deleteFolder(folder) }
                                        } label: {
                                            Label("Apagar pasta", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func listSection(_ model: SpeechListViewModel) -> some View {
        Section {
            ForEach(model.filteredSummaries) { summary in
                NavigationLink {
                    SpeechDetailView(speechID: summary.id)
                } label: {
                    row(summary)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Task { await model.toggleFavorite(summary) }
                    } label: {
                        Label(
                            summary.isFavorite ? "Remover dos favoritos" : "Favoritar",
                            systemImage: summary.isFavorite ? "star.slash" : "star"
                        )
                    }
                    .tint(.yellow)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        speechPendingDeletion = summary
                    } label: {
                        Label("Apagar", systemImage: "trash")
                    }
                    Button {
                        speechPendingMove = summary
                    } label: {
                        Label("Mover", systemImage: "folder")
                    }
                    .tint(.indigo)
                }
                .contextMenu {
                    Button {
                        Task { await model.toggleFavorite(summary) }
                    } label: {
                        Label(
                            summary.isFavorite ? "Remover dos favoritos" : "Favoritar",
                            systemImage: summary.isFavorite ? "star.slash" : "star"
                        )
                    }
                    Button {
                        speechPendingMove = summary
                    } label: {
                        Label("Mover para pasta", systemImage: "folder")
                    }
                    Button {
                        Task { await model.duplicate(summary) }
                    } label: {
                        Label("Duplicar", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        speechPendingDeletion = summary
                    } label: {
                        Label("Apagar", systemImage: "trash")
                    }
                }
            }
        } header: {
            HStack {
                Text("\(model.filteredSummaries.count) discurso(s)")
                Spacer()
                if model.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
    }

    private func row(_ summary: SpeechSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if summary.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                Text(summary.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 6)
                SpeechStatusChip(status: summary.status)
            }

            if !summary.subtitle.isEmpty {
                Text(summary.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                DurationText(minutes: summary.displayMinutes, prefix: "≈")
                Label("\(summary.sectionCount)", systemImage: "list.bullet")
                if summary.referenceCount > 0 {
                    Label("\(summary.referenceCount)", systemImage: "book.closed")
                }
                if summary.sourceCount > 0 {
                    Label("\(summary.sourceCount)", systemImage: "link")
                }
                Spacer()
                if !summary.occasion.isEmpty {
                    Text(summary.occasion)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if summary.preparationProgress > 0, summary.preparationProgress < 1 {
                PreparationProgressView(progress: summary.preparationProgress)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func filterChip(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(Color.secondary.opacity(0.10)),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear),
                        lineWidth: 1.5
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Barra de ferramentas

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    createSpeech(.blank)
                } label: {
                    Label("Discurso em branco", systemImage: "doc")
                }
                Button {
                    createSpeech(.talk)
                } label: {
                    Label("Discurso (introdução, corpo, conclusão)", systemImage: "text.book.closed")
                }
                Button {
                    createSpeech(.bibleStudy)
                } label: {
                    Label("Estudo bíblico", systemImage: "book.closed")
                }
                Divider()
                Button {
                    folderNameDraft = ""
                    isFolderAlertPresented = true
                } label: {
                    Label("Nova pasta…", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Criar discurso")
        }

        ToolbarItem(placement: .topBarLeading) {
            if let model {
                Menu {
                    Picker("Ordenar por", selection: Binding(
                        get: { model.sortOption },
                        set: { model.sortOption = $0 }
                    )) {
                        ForEach(SpeechSortOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Ordenar discursos")
            }
        }
    }

    // MARK: Ações

    private func prepareModel() async {
        // Aguarda a abertura do ambiente: as configurações (ordenação
        // preferida) e a biblioteca precisam estar carregadas antes do
        // primeiro carregamento da lista.
        await environment.start()
        if model == nil {
            model = SpeechListViewModel(repository: environment.speechRepository)
            model?.sortOption = environment.settings.preferredSpeechSort
        }
        await model?.load()
    }

    private func createSpeech(_ template: SpeechTemplate) {
        Task {
            if let speech = await model?.createSpeech(template: template) {
                await environment.saveSettings { $0.lastOpenedSpeechID = speech.id }
            }
        }
    }
}

#Preview {
    SpeechListView()
        .environment(AppEnvironment.preview())
}
