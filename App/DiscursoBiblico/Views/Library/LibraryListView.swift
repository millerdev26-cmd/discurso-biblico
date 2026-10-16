//
//  LibraryListView.swift
//  DiscursoBiblico
//
//  Biblioteca pessoal: materiais importados (EPUB, PDF, texto, Markdown,
//  HTML), categorias, favoritos e busca local no conteúdo — tudo offline.
//
//  A importação valida cada arquivo (extensão, tamanho, bytes iniciais, DRM,
//  duplicidade) e nunca interrompe os demais por causa de um arquivo ruim.
//

import DiscursoCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryListView: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var model: LibraryViewModel?
    @State private var isImporterPresented = false
    @State private var isReportPresented = false
    @State private var itemPendingDeletion: LibraryItem?
    @State private var categoryEditingItem: LibraryItem?
    @State private var categoryDraft = ""

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView("Carregando biblioteca…")
                }
            }
            .navigationTitle("Biblioteca")
            .toolbar { toolbar }
        }
        .task { await prepareModel() }
        .onAppear {
            if model != nil {
                Task { await model?.load() }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: Self.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await model?.importFiles(at: urls)
                    if model?.lastReport != nil {
                        isReportPresented = true
                    }
                }
            case .failure(let error):
                // O usuário cancelou ou algo impediu a escolha: nada é importado.
                print("Importação cancelada/falhou: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $isReportPresented) {
            if let report = model?.lastReport {
                ImportReportSheet(report: report) {
                    model?.dismissReport()
                    isReportPresented = false
                }
            }
        }
        .sheet(item: $categoryEditingItem) { item in
            CategoryEditorSheet(
                itemTitle: item.displayTitle,
                currentCategory: item.category,
                suggestions: model?.categorySuggestions(for: item) ?? [],
                draft: $categoryDraft
            ) { newCategory in
                let target = item
                Task { await model?.setCategory(newCategory, for: target) }
            }
        }
        .alert(
            "Apagar material?",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            ),
            presenting: itemPendingDeletion
        ) { item in
            Button("Apagar", role: .destructive) {
                Task { await model?.delete(item) }
                itemPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) { itemPendingDeletion = nil }
        } message: { item in
            Text("“\(item.displayTitle)” será removido da biblioteca e o arquivo apagado do aparelho.")
        }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func content(_ model: LibraryViewModel) -> some View {
        @Bindable var model = model

        List {
            if let message = model.errorMessage {
                MessageBanner(kind: .error, message: message)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            if model.isImporting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Importando e indexando…")
                        .font(.footnote)
                }
            }

            filtersSection(model)
            contentMatchesSection(model)
            itemsSection(model)

            if model.failedIndexCount > 0 {
                Section {
                    Text("\(model.failedIndexCount) material(is) não puderam ser indexados. Eles continuam disponíveis para leitura; toque em “Reindexar” para tentar de novo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $model.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Buscar título ou conteúdo"
        )
        .refreshable { await model.load() }
        .overlay {
            if model.items.isEmpty, !model.isLoading, !model.isImporting {
                EmptyStateView(
                    title: "Sua biblioteca está vazia",
                    message: "Importe um EPUB, PDF, texto ou Markdown. Os arquivos ficam neste aparelho e funcionam sem internet.",
                    systemImage: "books.vertical",
                    actionTitle: "Importar arquivo"
                ) {
                    isImporterPresented = true
                }
            } else if model.filteredItems.isEmpty, !model.items.isEmpty, model.searchText.isEmpty {
                ContentUnavailableView {
                    Label("Nada neste filtro", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Ajuste a categoria, o tipo ou os favoritos para ver mais materiais.")
                }
            }
        }
    }

    private func filtersSection(_ model: LibraryViewModel) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        title: "Todos",
                        systemImage: "tray.full",
                        isSelected: model.selectedCategory == nil && model.selectedKind == nil && !model.showsFavoritesOnly
                    ) {
                        model.selectedCategory = nil
                        model.selectedKind = nil
                        model.showsFavoritesOnly = false
                    }

                    filterChip(
                        title: "Favoritos",
                        systemImage: "star.fill",
                        isSelected: model.showsFavoritesOnly
                    ) {
                        model.showsFavoritesOnly.toggle()
                    }

                    ForEach(model.categories, id: \.self) { category in
                        filterChip(
                            title: category,
                            systemImage: "folder",
                            isSelected: model.selectedCategory == category
                        ) {
                            model.selectedCategory = model.selectedCategory == category ? nil : category
                        }
                    }

                    ForEach(model.kinds, id: \.self) { kind in
                        filterChip(
                            title: kind.displayName,
                            systemImage: kind.systemImageName,
                            isSelected: model.selectedKind == kind
                        ) {
                            model.selectedKind = model.selectedKind == kind ? nil : kind
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Text("\(model.filteredItems.count) material(is)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.indexedCount) pesquisável(is) · \(model.totalSizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func contentMatchesSection(_ model: LibraryViewModel) -> some View {
        let matches = model.contentMatches
        if !matches.isEmpty {
            Section {
                ForEach(matches.prefix(20)) { hit in
                    if let item = model.items.first(where: { $0.id == hit.itemID }) {
                        NavigationLink {
                            LibraryReaderView(item: item, initialLocator: hit.locator)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(hit.chapterTitle ?? hit.itemTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(hit.snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                if let locator = hit.locator {
                                    Text(locator.summaryText(chapterName: hit.chapterTitle))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } header: {
                Text("Trechos no conteúdo (\(matches.count))")
            } footer: {
                Text("A busca no conteúdo usa o índice local: funciona sem internet e mostra o ponto exato.")
            }
        }
    }

    private func itemsSection(_ model: LibraryViewModel) -> some View {
        Section("Materiais") {
            ForEach(model.filteredItems) { item in
                NavigationLink {
                    LibraryReaderView(item: item)
                } label: {
                    itemRow(item)
                }
                // Sem `simultaneousGesture` no link: ele chega a impedir a
                // navegação da linha. A data de "última abertura" é gravada
                // pelo leitor, ao abrir o material.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Task { await model.toggleFavorite(item) }
                    } label: {
                        Label(item.isFavorite ? "Desfavoritar" : "Favoritar", systemImage: item.isFavorite ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        itemPendingDeletion = item
                    } label: {
                        Label("Apagar", systemImage: "trash")
                    }
                    Button {
                        categoryDraft = item.category ?? ""
                        categoryEditingItem = item
                    } label: {
                        Label("Categoria", systemImage: "folder")
                    }
                    .tint(.indigo)
                }
                .contextMenu {
                    Button {
                        categoryDraft = item.category ?? ""
                        categoryEditingItem = item
                    } label: {
                        Label("Definir categoria…", systemImage: "folder")
                    }
                    Button {
                        Task { await model.reindex(item) }
                    } label: {
                        Label("Reindexar para busca", systemImage: "arrow.clockwise")
                    }
                    Button {
                        Task { await model.toggleFavorite(item) }
                    } label: {
                        Label(item.isFavorite ? "Desfavoritar" : "Favoritar", systemImage: item.isFavorite ? "star.slash" : "star")
                    }
                    Divider()
                    Button(role: .destructive) {
                        itemPendingDeletion = item
                    } label: {
                        Label("Apagar", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func itemRow(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: item.kind.systemImageName)
                    .foregroundStyle(.tint)
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                Spacer(minLength: 4)
                if item.isProtected {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Conteúdo protegido")
                }
            }

            HStack(spacing: 10) {
                Text(item.kind.displayName)
                if let author = item.author, !author.isEmpty {
                    Text(author).lineLimit(1)
                }
                Text(item.readableFileSize)
                if let category = item.category {
                    Label(category, systemImage: "folder")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if item.isReadableInsideApp, let progress = item.readingProgress, progress > 0 {
                PreparationProgressView(progress: progress, tint: .blue)
            }

            if item.indexStatus != .indexed {
                Text(item.indexStatus.displayName)
                    .font(.caption2)
                    .foregroundStyle(item.indexStatus == .failed ? .orange : .secondary)
            }
        }
        .padding(.vertical, 3)
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
            Button {
                isImporterPresented = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Importar material")
        }
    }

    // MARK: Apoio

    private static var importableTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .html, .epub]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        if let markdownLong = UTType(filenameExtension: "markdown") {
            types.append(markdownLong)
        }
        return types
    }

    private func prepareModel() async {
        // Aguarda a abertura do ambiente antes do primeiro carregamento.
        await environment.start()
        if model == nil {
            model = LibraryViewModel(
                repository: environment.libraryRepository,
                importer: environment.importer
            )
        }
        await model?.load()
    }
}

// MARK: - Folha de resultado da importação

private struct ImportReportSheet: View {

    let report: LibraryImportReport
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if !report.imported.isEmpty {
                    Section("Importados (\(report.imported.count))") {
                        ForEach(report.imported) { item in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayTitle).lineLimit(2)
                                    Text("\(item.kind.displayName) · \(item.readableFileSize)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                if !report.duplicates.isEmpty {
                    Section("Já estavam na biblioteca (\(report.duplicates.count))") {
                        ForEach(report.duplicates) { issue in
                            issueRow(issue, systemImage: "doc.on.doc", tint: .blue)
                        }
                    }
                }

                if !report.failures.isEmpty {
                    Section("Com problema (\(report.failures.count))") {
                        ForEach(report.failures) { issue in
                            issueRow(issue, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                        }
                    }
                }

                if !report.warnings.isEmpty {
                    Section {
                        ForEach(report.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.footnote)
                        }
                    } header: {
                        Text("Avisos")
                    } footer: {
                        Text("Avisos não impedem a leitura: eles explicam o que pode ter ficado de fora do índice.")
                    }
                }
            }
            .navigationTitle("Importação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Entendi", action: onClose)
                }
            }
        }
    }

    private func issueRow(_ issue: LibraryImportReport.Issue, systemImage: String, tint: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.fileName).lineLimit(1)
                Text(issue.message)
                    .font(.caption)
                if let recovery = issue.recovery {
                    Text(recovery)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Folha de categoria

private struct CategoryEditorSheet: View {

    let itemTitle: String
    let currentCategory: String?
    let suggestions: [String]
    @Binding var draft: String
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Categoria (ex.: Revistas, Livros)", text: $draft)
                } header: {
                    Text(itemTitle)
                }

                if !suggestions.isEmpty {
                    Section("Já usadas") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                draft = suggestion
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    LibraryListView()
        .environment(AppEnvironment.preview())
}
