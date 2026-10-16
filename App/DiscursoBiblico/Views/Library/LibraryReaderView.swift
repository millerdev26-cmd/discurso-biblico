//
//  LibraryReaderView.swift
//  DiscursoBiblico
//
//  Leitor dos materiais da biblioteca.
//
//  Por tipo de arquivo:
//   - EPUB: capítulos em ordem de leitura, com sumário, notas, marcadores e
//     destaques; o ponto de leitura é retomado no capítulo certo;
//   - PDF: páginas com o PDFKit, retomando a página salva;
//   - texto/Markdown/HTML: leitura corrida, com as mesmas anotações.
//
//  O leitor nunca contorna proteção de conteúdo: EPUB protegido e PDF com
//  senha são recusados com explicação.
//

import DiscursoCore
import PDFKit
import SwiftUI
import UIKit

struct LibraryReaderView: View {

    let item: LibraryItem
    var initialLocator: ReadingLocator?

    @Environment(AppEnvironment.self) private var environment

    @State private var currentItem: LibraryItem
    @State private var pdfDocument: PDFDocument?
    @State private var epubBook: EPUBBook?
    @State private var plainText: String?
    @State private var chapterIndex = 0
    @State private var currentPageIndex = 0
    @State private var loadErrorMessage: String?
    @State private var isLoading = true

    @State private var isNotesPresented = false
    @State private var isNoteEditorPresented = false
    @State private var noteDraft = ""
    @State private var noteLocator: ReadingLocator?
    @State private var scrollTarget: Int?

    @AppStorage("libraryReaderFontSize") private var readerFontSize: Double = 19
    @AppStorage("libraryReaderTheme") private var readerThemeRaw: String = ReadingTheme.system.rawValue

    init(item: LibraryItem, initialLocator: ReadingLocator? = nil) {
        self.item = item
        self.initialLocator = initialLocator
        _currentItem = State(initialValue: item)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Abrindo material…")
            } else if let loadErrorMessage {
                ContentUnavailableView {
                    Label("Não foi possível abrir", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadErrorMessage)
                } actions: {
                    Button("Tentar de novo") {
                        Task { await load() }
                    }
                }
            } else {
                readerContent
            }
        }
        .navigationTitle(currentItem.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task { await load() }
        .onChange(of: chapterIndex) { _, _ in
            Task { await savePosition() }
        }
        .onDisappear {
            Task { await savePosition() }
        }
        .sheet(isPresented: $isNotesPresented) {
            LibraryNotesSheet(
                item: currentItem,
                onDeleteNote: { id in update { $0.notes.removeAll { $0.id == id } } },
                onDeleteBookmark: { id in update { $0.bookmarks.removeAll { $0.id == id } } },
                onDeleteHighlight: { id in update { $0.highlights.removeAll { $0.id == id } } }
            )
        }
        .sheet(isPresented: $isNoteEditorPresented) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Escreva a nota", text: $noteDraft, axis: .vertical)
                            .lineLimit(3...10)
                    } footer: {
                        if let noteLocator {
                            Text("Anexada a \(noteLocator.summaryText(chapterName: currentChapterTitle))")
                        }
                    }
                }
                .navigationTitle("Nova nota")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") {
                            noteDraft = ""
                            isNoteEditorPresented = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salvar") {
                            addNote()
                        }
                        .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: Conteúdo por tipo

    @ViewBuilder
    private var readerContent: some View {
        if let pdfDocument {
            PDFDocumentView(
                document: pdfDocument,
                initialPageIndex: initialPageIndex,
                onPageChanged: { pageIndex in
                    currentPageIndex = pageIndex
                    Task { await savePosition() }
                }
            )
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                pageIndicator
            }
        } else if let epubBook {
            chapterReader
                .background(theme.background)
                .environment(\.colorScheme, theme.colorScheme ?? .light)
        } else if let plainText {
            textReader(plainText)
        } else {
            ContentUnavailableView {
                Label("Formato sem leitura interna", systemImage: "questionmark.square.dashed")
            } description: {
                Text("Este tipo de arquivo não tem leitor interno. Você ainda pode exportá-lo ou abri-lo em outro aplicativo.")
            }
        }
    }

    // MARK: EPUB e texto

    private var chapterReader: some View {
        let text = epubBook?.chapters.indices.contains(chapterIndex) == true
            ? epubBook?.chapters[chapterIndex].text ?? ""
            : ""
        return textReader(text, showsChapterHeader: true)
    }

    private func textReader(_ text: String, showsChapterHeader: Bool = false) -> some View {
        let paragraphs = paragraphs(in: text)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if showsChapterHeader, let chapter = currentChapter {
                        Text(chapter.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(theme.text)
                            .padding(.bottom, 4)
                    }

                    ForEach(paragraphs, id: \.offset) { paragraph in
                        paragraphView(paragraph)
                    }

                    if paragraphs.isEmpty {
                        Text("Este capítulo não tem texto extraível.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .onAppear { applyInitialScroll(using: proxy) }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                scrollTarget = nil
            }
            .onChange(of: chapterIndex) { _, _ in
                scrollTarget = paragraphs.first?.offset
            }
        }
    }

    private func paragraphView(_ paragraph: (offset: Int, text: String)) -> some View {
        let highlight = highlight(at: paragraph.offset)
        return Text(paragraph.text)
            .font(.system(size: readerFontSize, design: readerFontDesign))
            .foregroundStyle(theme.text)
            .lineSpacing(readerFontSize * 0.3)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                highlight.map { color(for: $0.color).opacity(0.35) } ?? Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Menu("Destacar") {
                    ForEach(Highlight.Color.allCases, id: \.self) { highlightColor in
                        Button(highlightColor.displayName) {
                            addHighlight(text: paragraph.text, offset: paragraph.offset, color: highlightColor)
                        }
                    }
                }
                if highlight != nil {
                    Button("Remover destaque") {
                        removeHighlight(at: paragraph.offset)
                    }
                }
                Button {
                    noteLocator = .chapter(
                        chapterIndex: chapterIndex,
                        offset: paragraph.offset,
                        length: paragraph.text.count
                    )
                    noteDraft = ""
                    isNoteEditorPresented = true
                } label: {
                    Label("Adicionar nota", systemImage: "note.text.badge.plus")
                }
                Button {
                    noteLocator = .chapter(
                        chapterIndex: chapterIndex,
                        offset: paragraph.offset,
                        length: paragraph.text.count
                    )
                    addBookmark(excerpt: paragraph.text)
                } label: {
                    Label("Marcar este ponto", systemImage: "bookmark")
                }
                Button {
                    Clipboard.copy(paragraph.text)
                    Haptics.tap()
                } label: {
                    Label("Copiar texto", systemImage: "doc.on.doc")
                }
            }
            .id(paragraph.offset)
    }

    // MARK: PDF

    private var pageIndicator: some View {
        Text("Página \(currentPageIndex + 1) de \(max(1, pdfDocument?.pageCount ?? 1))")
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 12)
    }

    // MARK: Barra de ferramentas

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if epubBook != nil {
            ToolbarItem(placement: .topBarLeading) {
                chapterMenu
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if pdfDocument == nil {
                appearanceMenu
            }
            Button {
                noteLocator = currentLocator()
                noteDraft = ""
                isNoteEditorPresented = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("Adicionar nota neste ponto")

            Button {
                isNotesPresented = true
            } label: {
                Image(systemName: annotationIcon)
            }
            .accessibilityLabel("Notas, marcadores e destaques")
        }
    }

    private var annotationIcon: String {
        let count = currentItem.notes.count + currentItem.bookmarks.count + currentItem.highlights.count
        return count > 0 ? "bookmark.circle.fill" : "bookmark.circle"
    }

    @ViewBuilder
    private var chapterMenu: some View {
        if let epubBook {
            Menu {
                ForEach(epubBook.chapters, id: \.id) { chapter in
                    Button {
                        chapterIndex = chapter.index
                    } label: {
                        if chapter.index == chapterIndex {
                            Label(chapter.title, systemImage: "checkmark")
                        } else {
                            Text(chapter.title)
                        }
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Sumário")
        }
    }

    private var appearanceMenu: some View {
        Menu {
            Section("Tamanho do texto") {
                Button {
                    readerFontSize = min(40, readerFontSize + 2)
                } label: {
                    Label("Aumentar", systemImage: "textformat.size.larger")
                }
                Button {
                    readerFontSize = max(12, readerFontSize - 2)
                } label: {
                    Label("Diminuir", systemImage: "textformat.size.smaller")
                }
            }
            Section("Tema") {
                ForEach(ReadingTheme.allCases, id: \.self) { theme in
                    Button {
                        readerThemeRaw = theme.rawValue
                    } label: {
                        if theme.rawValue == readerThemeRaw {
                            Label(theme.displayName, systemImage: "checkmark")
                        } else {
                            Text(theme.displayName)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "textformat.size")
        }
        .accessibilityLabel("Aparência da leitura")
    }

    // MARK: Carregamento

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        loadErrorMessage = nil
        pdfDocument = nil
        epubBook = nil
        plainText = nil
        // Marca o material como aberto agora (a lista só lia a data; aqui é
        // que sabemos que ele foi realmente aberto).
        update { $0.lastOpenedAt = Date() }

        guard let fileURL = await environment.libraryRepository.fileURL(for: currentItem) else {
            loadErrorMessage = "O arquivo deste material não está mais no armazenamento do aplicativo. Importe-o novamente."
            return
        }

        do {
            switch currentItem.kind {
            case .pdf:
                let data = try await Self.readData(at: fileURL)
                guard let document = PDFDocument(data: data) else {
                    loadErrorMessage = "O PDF não pôde ser aberto (arquivo corrompido ou protegido)."
                    return
                }
                if document.isLocked {
                    loadErrorMessage = "O PDF está protegido por senha. O aplicativo não contorna proteções: abra-o no aplicativo de origem e remova a proteção, se tiver direito."
                    return
                }
                pdfDocument = document
                currentPageIndex = min(
                    max(0, currentItem.lastReadPosition?.unitIndex ?? 0),
                    max(0, document.pageCount - 1)
                )
                if let pageIndex = initialLocator?.pageIndex {
                    currentPageIndex = min(max(0, pageIndex), max(0, document.pageCount - 1))
                }

            case .epub:
                let data = try await Self.readData(at: fileURL)
                let book = try await Task.detached(priority: .userInitiated) {
                    try EPUBParser.parse(data: data, includeHTML: false, verifyChecksums: true)
                }.value
                epubBook = book
                let saved = currentItem.lastReadPosition?.unitIndex ?? 0
                let target = initialLocator?.chapterIndex ?? saved
                chapterIndex = min(max(0, target), max(0, book.chapters.count - 1))
                if let offset = initialLocator?.characterOffset {
                    scrollTarget = offset
                }

            case .plainText, .markdown, .html:
                let data = try await Self.readData(at: fileURL)
                let raw = String(decoding: data, as: UTF8.self)
                plainText = currentItem.kind == .html ? HTMLTextExtractor.plainText(from: raw) : raw
                chapterIndex = initialLocator?.chapterIndex ?? 0

            case .unsupported:
                break
            }
        } catch let error as EPUBError {
            loadErrorMessage = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        } catch {
            loadErrorMessage = "Falha ao ler o arquivo (\(error.localizedDescription))."
        }
    }

    /// Lê os bytes fora do ator principal (arquivos grandes não travam a tela).
    private static func readData(at url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }

    // MARK: Posição e anotações

    private func savePosition() async {
        var updated = currentItem
        if pdfDocument != nil {
            updated.lastReadPosition = LibraryReadingPosition(
                unitIndex: currentPageIndex,
                fractionInsideUnit: 0,
                characterOffset: nil
            )
        } else if epubBook != nil {
            updated.lastReadPosition = LibraryReadingPosition(
                unitIndex: chapterIndex,
                fractionInsideUnit: 0,
                characterOffset: nil
            )
        } else {
            return
        }
        currentItem = updated
        try? await environment.libraryRepository.save(updated)
    }

    private func currentLocator() -> ReadingLocator {
        if let epubBook, epubBook.chapters.indices.contains(chapterIndex) {
            return .chapter(chapterIndex: chapterIndex, offset: 0, length: nil)
        }
        if pdfDocument != nil {
            return .page(pageIndex: currentPageIndex)
        }
        return .chapter(chapterIndex: 0, offset: 0, length: nil)
    }

    private func addNote() {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let locator = noteLocator ?? currentLocator()
        update { item in
            item.notes.append(LibraryNote(text: text, locator: locator))
        }
        noteDraft = ""
        noteLocator = nil
        isNoteEditorPresented = false
        Haptics.success()
    }

    private func addBookmark(excerpt: String) {
        let label = currentChapterTitle
        let locator = noteLocator ?? currentLocator()
        update { item in
            item.bookmarks.append(Bookmark(
                locator: locator,
                label: label,
                excerpt: String(excerpt.prefix(160))
            ))
        }
        noteLocator = nil
        Haptics.tap()
    }

    private func addHighlight(text: String, offset: Int, color: Highlight.Color) {
        let locator = ReadingLocator.chapter(
            chapterIndex: chapterIndex,
            offset: offset,
            length: text.count
        )
        update { item in
            item.highlights.removeAll { $0.locator.characterOffset == offset && $0.locator.chapterIndex == chapterIndex }
            item.highlights.append(Highlight(locator: locator, text: text, color: color))
        }
    }

    private func removeHighlight(at offset: Int) {
        update { item in
            item.highlights.removeAll {
                $0.locator.chapterIndex == chapterIndex && $0.locator.characterOffset == offset
            }
        }
    }

    /// Aplica uma alteração ao material e grava (notas, marcadores, destaques).
    private func update(_ mutate: (inout LibraryItem) -> Void) {
        var copy = currentItem
        mutate(&copy)
        currentItem = copy
        Task {
            try? await environment.libraryRepository.save(copy)
        }
    }

    // MARK: Apoio do texto

    private func paragraphs(in text: String) -> [(offset: Int, text: String)] {
        var result: [(offset: Int, text: String)] = []
        var offset = 0
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                result.append((offset, trimmed))
            }
            offset += line.count + 1
        }
        return result
    }

    private func highlight(at offset: Int) -> Highlight? {
        let chapter = currentChapterIndexForAnnotations
        return currentItem.highlights.first { highlight in
            guard highlight.locator.chapterIndex == chapter,
                  let start = highlight.locator.characterOffset else { return false }
            let length = highlight.locator.characterLength ?? 1
            return offset >= start && offset < start + length
        }
    }

    private var currentChapterIndexForAnnotations: Int {
        epubBook != nil ? chapterIndex : 0
    }

    private func applyInitialScroll(using proxy: ScrollViewProxy) {
        guard let target = initialLocator?.characterOffset else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private var currentChapter: EPUBChapter? {
        guard let epubBook, epubBook.chapters.indices.contains(chapterIndex) else { return nil }
        return epubBook.chapters[chapterIndex]
    }

    private var currentChapterTitle: String {
        currentChapter?.title ?? currentItem.displayTitle
    }

    private var initialPageIndex: Int {
        currentPageIndex
    }

    private var theme: ReaderThemeColors {
        ReaderThemeColors(theme: ReadingTheme(rawValue: readerThemeRaw) ?? .system)
    }

    private var readerFontDesign: Font.Design {
        .serif
    }

    private func color(for color: Highlight.Color) -> Color {
        switch color {
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .orange: return .orange
        }
    }
}

// MARK: - Cores do leitor

private struct ReaderThemeColors {

    let background: Color
    let text: Color
    let colorScheme: ColorScheme?

    init(theme: ReadingTheme) {
        switch theme {
        case .system:
            background = Color(.systemBackground)
            text = Color(.label)
            colorScheme = nil
        case .light:
            background = .white
            text = Color(red: 0.12, green: 0.12, blue: 0.13)
            colorScheme = .light
        case .sepia:
            background = Color(red: 0.97, green: 0.94, blue: 0.86)
            text = Color(red: 0.26, green: 0.20, blue: 0.12)
            colorScheme = .light
        case .dark:
            background = Color(red: 0.11, green: 0.11, blue: 0.12)
            text = Color(red: 0.92, green: 0.92, blue: 0.93)
            colorScheme = .dark
        case .highContrast:
            background = .black
            text = .white
            colorScheme = .dark
        }
    }
}

// MARK: - PDFKit

private struct PDFDocumentView: UIViewRepresentable {

    let document: PDFDocument
    let initialPageIndex: Int
    let onPageChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = .systemBackground
        context.coordinator.attach(to: view)

        let pageIndex = initialPageIndex
        DispatchQueue.main.async {
            if let page = document.page(at: max(0, min(pageIndex, document.pageCount - 1))) {
                view.go(to: page)
            }
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        context.coordinator.onPageChanged = onPageChanged
    }

    final class Coordinator {

        var onPageChanged: (Int) -> Void
        private weak var view: PDFView?
        private var observer: NSObjectProtocol?

        init(onPageChanged: @escaping (Int) -> Void) {
            self.onPageChanged = onPageChanged
        }

        func attach(to view: PDFView) {
            self.view = view
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self] _ in
                guard let self, let view = self.view,
                      let page = view.currentPage,
                      let index = view.document?.index(for: page) else { return }
                self.onPageChanged(index)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

// MARK: - Notas, marcadores e destaques

private struct LibraryNotesSheet: View {

    let item: LibraryItem
    let onDeleteNote: (UUID) -> Void
    let onDeleteBookmark: (UUID) -> Void
    let onDeleteHighlight: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if item.notes.isEmpty, item.bookmarks.isEmpty, item.highlights.isEmpty {
                    ContentUnavailableView {
                        Label("Nada anotado ainda", systemImage: "note.text")
                    } description: {
                        Text("Toque em um trecho para destacar, marcar o ponto ou escrever uma nota.")
                    }
                }

                if !item.notes.isEmpty {
                    Section("Notas (\(item.notes.count))") {
                        ForEach(item.notes) { note in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.text)
                                if let locator = note.locator {
                                    Text(locator.summaryText())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    onDeleteNote(note.id)
                                } label: {
                                    Label("Apagar", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if !item.bookmarks.isEmpty {
                    Section("Marcadores (\(item.bookmarks.count))") {
                        ForEach(item.bookmarks) { bookmark in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bookmark.label.isEmpty ? bookmark.locator.summaryText() : bookmark.label)
                                if let excerpt = bookmark.excerpt, !excerpt.isEmpty {
                                    Text(excerpt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    onDeleteBookmark(bookmark.id)
                                } label: {
                                    Label("Apagar", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if !item.highlights.isEmpty {
                    Section("Destaques (\(item.highlights.count))") {
                        ForEach(item.highlights) { highlight in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(highlight.text)
                                    .lineLimit(3)
                                Text("\(highlight.color.displayName)\(highlight.locator.chapterIndex.map { " · Capítulo \($0 + 1)" } ?? "")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    onDeleteHighlight(highlight.id)
                                } label: {
                                    Label("Apagar", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Anotações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LibraryReaderView(
            item: LibraryItem(
                title: "Exemplo",
                kind: .plainText,
                fileName: "exemplo.txt",
                fileExtension: "txt"
            )
        )
        .environment(AppEnvironment.preview())
    }
}
