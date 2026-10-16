//
//  SpeechEditorView.swift
//  DiscursoBiblico
//
//  Editor do discurso: metadados, tópicos, blocos estruturados, referências
//  bíblicas, notas, marcações e fontes.
//
//  Salvamento: cada alteração passa pelo `AutosaveCoordinator` (gravação com
//  atraso) e o botão "Salvar agora" grava na hora. Ao tocar em "Pronto", o
//  que estiver pendente é gravado antes de fechar.
//
//  Marcações em linha aceitas nos textos:
//      *ênfase*   {pausa}   {pausa: 3}   {tom: solene}   {transição: ...}
//      {lento}    {rápido}  {olhar}      {nota: ...}
//

import DiscursoCore
import SwiftUI

struct SpeechEditorView: View {

    let speech: Speech

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var model: SpeechEditorViewModel?
    @State private var reader = SpeechReaderService()
    @State private var editMode: EditMode = .inactive
    @State private var referenceEditingBlockID: UUID?
    @State private var tagDraft = ""
    @State private var blockPendingDeletion: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView("Abrindo editor…")
                }
            }
            .navigationTitle("Editar discurso")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar { toolbar }
        }
        .task { await prepare() }
        .onDisappear {
            reader.stop()
            Task { await model?.finishEditing() }
        }
        .sheet(item: Binding(
            get: { referenceEditingBlockID.map { ReferenceTarget(id: $0) } },
            set: { if $0 == nil { referenceEditingBlockID = nil } }
        )) { target in
            BibleReferencePicker(initial: model.flatMap { block(withID: target.id, in: $0)?.reference }) { reference in
                model?.setBlockReference(reference, blockID: target.id)
            }
        }
        .alert(
            "Apagar bloco?",
            isPresented: Binding(
                get: { blockPendingDeletion != nil },
                set: { if !$0 { blockPendingDeletion = nil } }
            )
        ) {
            Button("Apagar", role: .destructive) {
                if let id = blockPendingDeletion {
                    model?.deleteBlock(blockID: id)
                }
                blockPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) { blockPendingDeletion = nil }
        }
    }

    private struct ReferenceTarget: Identifiable {
        let id: UUID
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func content(_ model: SpeechEditorViewModel) -> some View {
        List {
            saveStatusSection(model)
            metadataSection(model)
            ForEach(Array(model.speech.sections.enumerated()), id: \.element.id) { index, section in
                sectionRows(model, index: index, section: section)
            }
            addSectionRow(model)
            helpSection
        }
        .listStyle(.insetGrouped)
    }

    private func saveStatusSection(_ model: SpeechEditorViewModel) -> some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: saveIcon(model.saveState))
                    .foregroundStyle(saveTint(model.saveState))
                Text(saveText(model.saveState))
                    .font(.footnote)
                Spacer()
                Text(model.durationSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let message = model.errorMessage {
                MessageBanner(kind: .error, message: message)
            }
        }
    }

    // MARK: Metadados

    private func metadataSection(_ model: SpeechEditorViewModel) -> some View {
        Section("Identificação") {
            TextField("Título", text: Binding(
                get: { model.speech.title },
                set: { model.setTitle($0) }
            ))
            .font(.headline)

            TextField("Subtítulo (opcional)", text: Binding(
                get: { model.speech.subtitle },
                set: { model.setSubtitle($0) }
            ))

            TextField("Ocasião (ex.: Discurso público)", text: Binding(
                get: { model.speech.occasion },
                set: { model.setOccasion($0) }
            ))
            .onSubmit {
                Task { await environment.noteRecentOccasion(model.speech.occasion) }
            }

            if !environment.settings.recentOccasions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(environment.settings.recentOccasions, id: \.self) { occasion in
                            Button(occasion) {
                                model.setOccasion(occasion)
                            }
                            .font(.footnote)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Picker("Situação", selection: Binding(
                get: { model.speech.status },
                set: { model.setStatus($0) }
            )) {
                ForEach(SpeechStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }

            Toggle("Favorito", isOn: Binding(
                get: { model.speech.isFavorite },
                set: { _ in model.toggleFavorite() }
            ))

            Menu {
                Button("Sem tempo planejado") { model.setPlannedMinutes(nil) }
                ForEach([5.0, 8.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0], id: \.self) { minutes in
                    Button("\(Int(minutes)) min") { model.setPlannedMinutes(minutes) }
                }
            } label: {
                IconTextLabel(
                    systemImage: "timer",
                    text: model.speech.plannedMinutes.map { "Planejado: \(Int($0)) min" } ?? "Definir tempo planejado"
                )
            }

            tagsRows(model)

            DisclosureGroup("Notas particulares do discurso") {
                TextField(
                    "Anotações que não aparecem na apresentação",
                    text: Binding(
                        get: { model.speech.privateNotes },
                        set: { model.setPrivateNotes($0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(3...10)
            }
        }
    }

    @ViewBuilder
    private func tagsRows(_ model: SpeechEditorViewModel) -> some View {
        if !model.speech.tags.isEmpty {
            HStack {
                ForEach(model.speech.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                            .font(.caption)
                        Button {
                            model.removeTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remover etiqueta \(tag)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
        }
        HStack {
            TextField("Nova etiqueta", text: $tagDraft)
                .onSubmit { addTag(model) }
            Button("Adicionar") { addTag(model) }
                .disabled(tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if !environment.settings.recentTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(environment.settings.recentTags, id: \.self) { tag in
                        Button("#\(tag)") {
                            model.addTag(tag)
                            Task { await environment.noteRecentTag(tag) }
                        }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Tópicos

    @ViewBuilder
    private func sectionRows(_ model: SpeechEditorViewModel, index: Int, section: SpeechSection) -> some View {
        Section {
            ForEach(section.blocks) { block in
                blockEditor(model, block: block)
            }
            .onMove { source, destination in
                model.moveBlocks(inSection: section.id, from: source, to: destination)
            }

            Menu {
                ForEach(SpeechBlockKind.allCases, id: \.self) { kind in
                    Button {
                        if let id = model.addBlock(kind: kind, toSection: section.id) {
                            model.selectedBlockID = id
                        }
                    } label: {
                        Label(kind.displayName, systemImage: kind.systemImageName)
                    }
                }
            } label: {
                Label("Adicionar bloco", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Button {
                    model.toggleSectionCompleted(id: section.id)
                } label: {
                    Image(systemName: section.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(section.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.isCompleted ? "Marcar tópico como não concluído" : "Marcar tópico como concluído")

                Text("Tópico \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button {
                        Task { await moveSection(model, id: section.id, by: -1) }
                    } label: {
                        Label("Mover para cima", systemImage: "arrow.up")
                    }
                    .disabled(index == 0)

                    Button {
                        Task { await moveSection(model, id: section.id, by: 1) }
                    } label: {
                        Label("Mover para baixo", systemImage: "arrow.down")
                    }
                    .disabled(index >= model.speech.sections.count - 1)

                    Button {
                        model.duplicateSection(id: section.id)
                    } label: {
                        Label("Duplicar tópico", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        model.deleteSection(id: section.id)
                    } label: {
                        Label("Apagar tópico", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Ações do tópico \(index + 1)")
            }
        } footer: {
            if !section.references.isEmpty {
                Text("Referências neste tópico: " + section.references.map(\.abbreviatedText).joined(separator: ", "))
                    .font(.caption2)
            }
        }
        .headerProminence(.increased)
    }

    @ViewBuilder
    private func addSectionRow(_ model: SpeechEditorViewModel) -> some View {
        Section {
            Button {
                _ = model.addSection()
            } label: {
                Label("Adicionar tópico", systemImage: "plus")
            }
        }
    }

    private var helpSection: some View {
        Section {
            DisclosureGroup("Como escrever as marcações") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("*ênfase* — destaca uma palavra ou frase")
                    Text("{pausa} ou {pausa: 3} — pausa na fala (segundos opcionais)")
                    Text("{tom: solene} — mudança de tom")
                    Text("{transição: próximo ponto} — transição")
                    Text("{lento} / {rápido} — ritmo da fala")
                    Text("{olhar} — contato visual com a assistência")
                    Text("{nota: ...} — observação particular em linha")
                    Text("Referências como “João 3:16” são reconhecidas e destacadas automaticamente.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } footer: {
            Text("As notas do apresentador e os blocos do tipo “Nota” não aparecem na apresentação, a menos que você ligue isso nas preferências.")
        }
    }

    // MARK: Blocos

    @ViewBuilder
    private func blockEditor(_ model: SpeechEditorViewModel, block: SpeechBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: block.kind.systemImageName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(SpeechBlockKind.allCases, id: \.self) { kind in
                        Button {
                            model.setBlockKind(kind, blockID: block.id)
                        } label: {
                            Label(kind.displayName, systemImage: kind.systemImageName)
                        }
                    }
                } label: {
                    Text(block.kind.displayName)
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("Tipo do bloco")

                if block.isHighlighted {
                    Image(systemName: "highlighter")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if block.isPresenterNote || block.kind == .note {
                    Image(systemName: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                blockMenu(model, block: block)
            }

            blockContent(model, block: block)
        }
        .padding(.vertical, 4)
        .listRowBackground(
            model.selectedBlockID == block.id
                ? Color.accentColor.opacity(0.08)
                : Color(.secondarySystemGroupedBackground)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                blockPendingDeletion = block.id
            } label: {
                Label("Apagar", systemImage: "trash")
            }
            Button {
                model.toggleBlockHighlight(blockID: block.id)
            } label: {
                Label("Destacar", systemImage: "highlighter")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func blockContent(_ model: SpeechEditorViewModel, block: SpeechBlock) -> some View {
        switch block.kind {
        case .bulletList:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(block.items.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        TextField("Item \(index + 1)", text: Binding(
                            get: { itemText(model, blockID: block.id, index: index) },
                            set: { model.updateBullet(at: index, text: $0, blockID: block.id) }
                        ), axis: .vertical)
                        .lineLimit(1...5)
                        Button {
                            model.removeBullet(at: index, blockID: block.id)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remover item \(index + 1)")
                    }
                }
                Button {
                    model.addBullet("", blockID: block.id)
                } label: {
                    Label("Adicionar item", systemImage: "plus.circle")
                        .font(.footnote)
                }
            }

        case .scripture:
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    referenceEditingBlockID = block.id
                } label: {
                    HStack {
                        Image(systemName: "book.closed")
                        Text(block.reference?.displayText ?? "Escolher referência")
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if let reference = block.reference {
                    Text(reference.officialWebURL()?.absoluteString ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                TextField(
                    "Texto do versículo (opcional; use apenas o que você tem direito de usar)",
                    text: textBinding(model, blockID: block.id),
                    axis: .vertical
                )
                .lineLimit(2...8)
            }

        case .cue:
            VStack(alignment: .leading, spacing: 6) {
                Picker("Indicação", selection: Binding(
                    get: { block.cue ?? .pause },
                    set: { model.setBlockCue($0, detail: block.cueDetail, blockID: block.id) }
                )) {
                    ForEach(CueKind.allCases, id: \.self) { cue in
                        Text(cue.displayName).tag(cue)
                    }
                }
                TextField("Detalhe (ex.: “3 s”, “tom solene”)", text: Binding(
                    get: { block(withID: block.id, in: model)?.cueDetail ?? "" },
                    set: { model.setBlockCue(block.cue ?? .pause, detail: $0.isEmpty ? nil : $0, blockID: block.id) }
                ))
            }

        case .divider:
            Divider()

        default:
            TextField(
                placeholder(for: block.kind),
                text: textBinding(model, blockID: block.id),
                axis: .vertical
            )
            .lineLimit(1...12)
            .font(block.kind == .heading || block.kind == .subheading ? .headline : .body)
        }
    }

    private func blockMenu(_ model: SpeechEditorViewModel, block: SpeechBlock) -> some View {
        Menu {
            Button {
                let text = block.spokenText.isEmpty ? block.text : block.spokenText
                if reader.currentBlockID == block.id, reader.isSpeaking {
                    reader.stop()
                } else {
                    reader.speak(text, identifier: block.id)
                }
            } label: {
                Label(
                    reader.currentBlockID == block.id && reader.isSpeaking ? "Parar leitura" : "Ouvir este bloco",
                    systemImage: "speaker.wave.2"
                )
            }

            Button {
                model.toggleBlockHighlight(blockID: block.id)
            } label: {
                Label(block.isHighlighted ? "Remover destaque" : "Destacar", systemImage: "highlighter")
            }

            Button {
                model.toggleBlockPresenterNote(blockID: block.id)
            } label: {
                Label(
                    block.isPresenterNote ? "Mostrar na apresentação" : "Marcar como nota do apresentador",
                    systemImage: block.isPresenterNote ? "eye" : "eye.slash"
                )
            }

            Divider()

            Button {
                moveBlock(model, sectionID: sectionID(of: block.id, in: model), blockID: block.id, by: -1)
            } label: {
                Label("Mover para cima", systemImage: "arrow.up")
            }

            Button {
                moveBlock(model, sectionID: sectionID(of: block.id, in: model), blockID: block.id, by: 1)
            } label: {
                Label("Mover para baixo", systemImage: "arrow.down")
            }

            Divider()

            Button(role: .destructive) {
                blockPendingDeletion = block.id
            } label: {
                Label("Apagar bloco", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Ações do bloco \(block.kind.displayName)")
    }

    // MARK: Apoio do editor

    private func textBinding(_ model: SpeechEditorViewModel, blockID: UUID) -> Binding<String> {
        Binding(
            get: { block(withID: blockID, in: model)?.text ?? "" },
            set: { model.setBlockText($0, blockID: blockID) }
        )
    }

    private func itemText(_ model: SpeechEditorViewModel, blockID: UUID, index: Int) -> String {
        guard let block = block(withID: blockID, in: model),
              block.items.indices.contains(index) else { return "" }
        return block.items[index]
    }

    private func block(withID id: UUID, in model: SpeechEditorViewModel) -> SpeechBlock? {
        for section in model.speech.sections {
            if let block = section.blocks.first(where: { $0.id == id }) {
                return block
            }
        }
        return nil
    }

    private func sectionID(of blockID: UUID, in model: SpeechEditorViewModel) -> UUID? {
        for section in model.speech.sections where section.blocks.contains(where: { $0.id == blockID }) {
            return section.id
        }
        return nil
    }

    private func moveBlock(
        _ model: SpeechEditorViewModel,
        sectionID: UUID?,
        blockID: UUID,
        by offset: Int
    ) {
        guard let sectionID,
              let section = model.speech.sections.first(where: { $0.id == sectionID }),
              let current = section.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let target = current + offset
        guard section.blocks.indices.contains(target) else { return }
        model.moveBlocks(
            inSection: sectionID,
            from: IndexSet(integer: current),
            to: offset > 0 ? target + 1 : target
        )
    }

    private func moveSection(_ model: SpeechEditorViewModel, id: UUID, by offset: Int) async {
        guard let current = model.speech.sections.firstIndex(where: { $0.id == id }) else { return }
        let target = current + offset
        guard model.speech.sections.indices.contains(target) else { return }
        model.moveSections(
            from: IndexSet(integer: current),
            to: offset > 0 ? target + 1 : target
        )
    }

    private func addTag(_ model: SpeechEditorViewModel) {
        let tag = tagDraft
        tagDraft = ""
        model.addTag(tag)
        Task { await environment.noteRecentTag(tag) }
    }

    private func placeholder(for kind: SpeechBlockKind) -> String {
        switch kind {
        case .heading: return "Título do tópico"
        case .subheading: return "Subtítulo"
        case .quote: return "Citação"
        case .note: return "Observação para mim (não aparece na apresentação)"
        default: return "Escreva aqui…"
        }
    }

    // MARK: Estado do salvamento

    private func saveIcon(_ state: AutosaveCoordinator.State) -> String {
        switch state {
        case .idle: return "checkmark.circle"
        case .pending: return "clock"
        case .saving: return "arrow.triangle.2.circlepath"
        case .saved: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func saveTint(_ state: AutosaveCoordinator.State) -> Color {
        switch state {
        case .failed: return .red
        case .saved: return .green
        default: return .secondary
        }
    }

    private func saveText(_ state: AutosaveCoordinator.State) -> String {
        switch state {
        case .idle: return "Tudo salvo"
        case .pending: return "Alterações aguardando salvamento…"
        case .saving: return "Salvando…"
        case .saved(let date): return "Salvo às \(Self.timeText(date))"
        case .failed(let message, _): return "Falha ao salvar: \(message)"
        }
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: Barra de ferramentas

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Pronto") {
                Task {
                    if let occasion = model?.speech.occasion, !occasion.isEmpty {
                        await environment.noteRecentOccasion(occasion)
                    }
                    await model?.finishEditing()
                    dismiss()
                }
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            Button(editMode == .active ? "OK" : "Reordenar") {
                withAnimation {
                    editMode = editMode == .active ? .inactive : .active
                }
            }
            .disabled(model?.speech.sections.isEmpty ?? true)
            .accessibilityLabel(editMode == .active ? "Concluir reordenação" : "Reordenar blocos")
        }

        ToolbarItem(placement: .bottomBar) {
            Button {
                Task { await model?.saveNow() }
            } label: {
                Label("Salvar agora", systemImage: "square.and.arrow.down")
            }
        }
    }

    // MARK: Preparação

    private func prepare() async {
        guard model == nil else { return }
        model = SpeechEditorViewModel(
            speech: speech,
            repository: environment.speechRepository,
            autosave: environment.makeAutosaveCoordinator(),
            wordsPerMinute: environment.settings.wordsPerMinute
        )
    }
}

#Preview {
    SpeechEditorView(speech: Speech(title: "Exemplo", sections: [
        SpeechSection(title: "Introdução", blocks: [.heading("Introdução"), .paragraph("Boa noite a todos.")])
    ]))
    .environment(AppEnvironment.preview())
}
