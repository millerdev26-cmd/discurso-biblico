//
//  SpeechDetailView.swift
//  DiscursoBiblico
//
//  Visão geral de um discurso: resumo, tópicos, referências, fontes,
//  exportação, leitura em voz alta e as portas de entrada (editar/proferir).
//

import DiscursoCore
import SwiftUI
import UIKit

struct SpeechDetailView: View {

    let speechID: UUID
    var startsInPresentation = false

    @Environment(AppEnvironment.self) private var environment

    @State private var model: SpeechDetailViewModel?
    @State private var reader = SpeechReaderService()

    @State private var isEditorPresented = false
    @State private var isPresentationPresented = false
    @State private var didAutoPresent = false
    @State private var shareOutcome: SpeechDetailViewModel.ExportOutcome?
    @State private var passage: PassageRequest?
    @State private var isDeleteAlertPresented = false
    @State private var readAloudRate: Float = 0.5

    /// Envelope identificável para o painel do trecho bíblico.
    struct PassageRequest: Identifiable {
        let id = UUID()
        let reference: BibleReference
    }

    var body: some View {
        Group {
            if let model, let speech = model.speech {
                content(model, speech: speech)
            } else if let message = model?.errorMessage {
                ContentUnavailableView {
                    Label("Não foi possível abrir", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            } else {
                ProgressView("Abrindo discurso…")
            }
        }
        .navigationTitle(model?.speech?.displayTitle ?? "Discurso")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onAppear {
            if model != nil {
                Task { await model?.load(id: speechID) }
            }
            if startsInPresentation, !didAutoPresent {
                didAutoPresent = true
                isPresentationPresented = true
            }
        }
        .onDisappear {
            reader.stop()
        }
        .sheet(isPresented: $isEditorPresented) {
            if let speech = model?.speech {
                SpeechEditorView(speech: speech)
                    .environment(environment)
            }
        }
        .fullScreenCover(isPresented: $isPresentationPresented) {
            PresentationView(speechID: speechID)
                .environment(environment)
        }
        .sheet(item: $shareOutcome) { outcome in
            ShareSheet(items: [outcome.fileURL])
        }
        .sheet(item: $passage) { request in
            BiblePassagePanel(reference: request.reference)
                .environment(environment)
        }
        .alert("Apagar discurso?", isPresented: $isDeleteAlertPresented) {
            Button("Apagar", role: .destructive) {
                Task {
                    try? await environment.speechRepository.delete(id: speechID)
                    await environment.saveSettings { $0.lastOpenedSpeechID = nil }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O discurso será apagado do aparelho. Esta ação não pode ser desfeita.")
        }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func content(_ model: SpeechDetailViewModel, speech: Speech) -> some View {
        List {
            if let message = model.errorMessage {
                MessageBanner(kind: .error, message: message)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            headerSection(model, speech: speech)
            summarySection(model, speech: speech)
            sectionsOverview(speech)
            referencesSection(speech)
            sourcesSection(speech)
            exportSection(model)
            readAloudSection(speech)
            actionsSection(model, speech: speech)
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isPresentationPresented = true
                } label: {
                    Image(systemName: "play.rectangle")
                }
                .accessibilityLabel("Abrir no modo de proferimento")

                Button {
                    isEditorPresented = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Editar discurso")

                Button {
                    Task { await model.toggleFavorite() }
                } label: {
                    Image(systemName: speech.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(speech.isFavorite ? .yellow : .primary)
                }
                .accessibilityLabel(speech.isFavorite ? "Remover dos favoritos" : "Favoritar")
            }
        }
    }

    private func headerSection(_ model: SpeechDetailViewModel, speech: Speech) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(speech.displayTitle)
                    .font(.title3.weight(.semibold))
                if !speech.subtitle.isEmpty {
                    Text(speech.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    SpeechStatusChip(status: speech.status)
                    if !speech.occasion.isEmpty {
                        Label(speech.occasion, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !speech.tags.isEmpty {
                    Text(speech.tags.map { "#\($0)" }.joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            Picker("Situação", selection: Binding(
                get: { speech.status },
                set: { status in Task { await model.setStatus(status) } }
            )) {
                ForEach(SpeechStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }

            Menu {
                Button("Sem tempo planejado") {
                    Task { await model.setPlannedMinutes(nil) }
                }
                ForEach([5.0, 8.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0], id: \.self) { minutes in
                    Button("\(Int(minutes)) min") {
                        Task { await model.setPlannedMinutes(minutes) }
                    }
                }
            } label: {
                IconTextLabel(
                    systemImage: "timer",
                    text: speech.plannedMinutes.map { "Planejado: \(Int($0)) min" } ?? "Definir tempo planejado"
                )
            }
            .accessibilityLabel("Tempo planejado")
        }
    }

    private func summarySection(_ model: SpeechDetailViewModel, speech: Speech) -> some View {
        Section("Resumo") {
            IconTextLabel(systemImage: "stopwatch", text: model.durationSummary)
            IconTextLabel(systemImage: "text.word.spacing", text: "\(speech.wordCount) palavra(s) a proferir")
            IconTextLabel(
                systemImage: "list.bullet",
                text: "\(speech.sections.count) tópico(s), \(speech.allBlocks.count) bloco(s)"
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Preparação")
                    Spacer()
                    Text("\(Int((speech.preparationProgress * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                PreparationProgressView(progress: speech.preparationProgress)
            }
            if speech.preparationProgress < 1 {
                Button {
                    Task { await model.markPrepared() }
                } label: {
                    Label("Marcar tudo como preparado", systemImage: "checkmark.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func sectionsOverview(_ speech: Speech) -> some View {
        Section("Tópicos") {
            ForEach(Array(speech.sections.enumerated()), id: \.element.id) { index, section in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: section.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(section.isCompleted ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(index + 1). \(section.displayTitle)")
                            .lineLimit(1)
                        let blocks = section.blocks.count
                        Text("\(blocks) bloco(s) · \(section.wordCount) palavra(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            Button {
                isEditorPresented = true
            } label: {
                Label("Editar tópicos e conteúdo", systemImage: "square.and.pencil")
            }
        }
    }

    @ViewBuilder
    private func referencesSection(_ speech: Speech) -> some View {
        let references = speech.references
        if !references.isEmpty {
            Section("Referências bíblicas") {
                ForEach(references, id: \.self) { reference in
                    Button {
                        passage = PassageRequest(reference: reference)
                    } label: {
                        HStack {
                            Image(systemName: "book.closed")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reference.displayText)
                                    .foregroundStyle(.primary)
                                Text(reference.summarizedText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func sourcesSection(_ speech: Speech) -> some View {
        let sources = speech.allSources
        if !sources.isEmpty {
            Section("Fontes") {
                ForEach(sources) { source in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: source.kind.systemImageName)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.displayTitle)
                                .lineLimit(2)
                            if let subtitle = source.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let url = source.url {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                Image(systemName: "safari")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Abrir fonte no navegador")
                        }
                    }
                }
            }
        }
    }

    private func exportSection(_ model: SpeechDetailViewModel) -> some View {
        Section {
            Picker("Formato", selection: Binding(
                get: { model.exportFormat },
                set: { model.exportFormat = $0 }
            )) {
                ForEach(SpeechExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            Toggle("Incluir notas do apresentador", isOn: Binding(
                get: { model.includePresenterNotes },
                set: { model.includePresenterNotes = $0 }
            ))
            Toggle("Incluir fontes", isOn: Binding(
                get: { model.includeSources },
                set: { model.includeSources = $0 }
            ))
            Toggle("Incluir informações (título, data)", isOn: Binding(
                get: { model.includeMetadata },
                set: { model.includeMetadata = $0 }
            ))
            Button {
                Task {
                    await model.export()
                    if let outcome = model.lastExport {
                        shareOutcome = outcome
                    }
                }
            } label: {
                Label("Gerar arquivo e compartilhar", systemImage: "square.and.arrow.up")
            }
            if let message = model.lastExport?.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Exportação")
        } footer: {
            Text("O arquivo é gerado no aparelho. O compartilhamento só acontece se você escolher um destino.")
        }
    }

    private func readAloudSection(_ speech: Speech) -> some View {
        Section {
            HStack(spacing: 14) {
                Button {
                    if reader.isSpeaking && !reader.isPaused {
                        reader.pause()
                    } else if reader.isPaused {
                        reader.resume()
                    } else {
                        let text = speech.plainText(includePresenterNotes: false)
                        reader.speak(text, rate: readAloudRate)
                    }
                } label: {
                    Image(systemName: reader.isSpeaking && !reader.isPaused ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reader.isSpeaking ? "Pausar leitura em voz alta" : "Ouvir o discurso")

                Button {
                    reader.stop()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(!reader.isSpeaking && !reader.isPaused)
                .accessibilityLabel("Parar leitura")

                VStack(alignment: .leading, spacing: 2) {
                    Text(reader.isSpeaking ? (reader.isPaused ? "Pausado" : "Lendo em voz alta…") : "Ouvir durante a preparação")
                        .font(.subheadline)
                    Text("Voz do sistema, em português, sem usar a internet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Slider(value: $readAloudRate, in: 0.3...0.7) {
                Text("Velocidade da voz")
            }
            .accessibilityValue("\(Int(readAloudRate * 100)) por cento")
        } header: {
            Text("Leitura em voz alta")
        }
    }

    private func actionsSection(_ model: SpeechDetailViewModel, speech: Speech) -> some View {
        Section {
            Button {
                isPresentationPresented = true
            } label: {
                Label("Apresentar agora", systemImage: "play.rectangle.fill")
            }
            Button {
                isEditorPresented = true
            } label: {
                Label("Editar discurso", systemImage: "square.and.pencil")
            }
            if speech.lastReadPosition != nil {
                Button {
                    Task { await model.resetReadingPosition() }
                } label: {
                    Label("Reiniciar ponto de leitura", systemImage: "arrow.counterclockwise")
                }
            }
            Button(role: .destructive) {
                isDeleteAlertPresented = true
            } label: {
                Label("Apagar discurso", systemImage: "trash")
            }
        } header: {
            Text("Ações")
        } footer: {
            Text("O ponto de leitura volta exatamente onde você parou da próxima vez.")
        }
    }

    // MARK: Ações

    private func load() async {
        if model == nil {
            model = SpeechDetailViewModel(repository: environment.speechRepository)
        }
        await model?.load(id: speechID)
        // "Continuar de onde parei" na lista: registra aqui (ao abrir), e não
        // com um gesto sobre o `NavigationLink` — que chegava a impedir a
        // própria navegação da lista.
        await environment.saveSettings { $0.lastOpenedSpeechID = speechID }
    }
}

#Preview {
    NavigationStack {
        SpeechDetailView(speechID: UUID())
            .environment(AppEnvironment.preview())
    }
}
