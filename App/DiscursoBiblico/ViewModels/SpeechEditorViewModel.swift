//
//  SpeechEditorViewModel.swift
//  DiscursoBiblico
//
//  Edição de um discurso: tópicos, blocos, marcações, referências e notas.
//
//  Cada alteração passa por `mutate`, que:
//   1. atualiza `updatedAt` e recalcula os campos derivados (duração etc.);
//   2. entrega o discurso ao `AutosaveCoordinator` (gravação com atraso);
//   3. publica o estado do salvamento para a interface.
//
//  O editor também oferece "Salvar agora" e gravação ao sair — nada depende
//  de o usuário esperar o temporizador.
//

import DiscursoCore
import Foundation
import Observation

@MainActor
@Observable
final class SpeechEditorViewModel {

    private(set) var speech: Speech
    private(set) var saveState: AutosaveCoordinator.State = .idle
    private(set) var errorMessage: String?

    var wordsPerMinute: Double = SpeechDurationEstimator.defaultWordsPerMinute

    /// Bloco em edição (destaque na lista).
    var selectedBlockID: UUID?

    private let repository: any SpeechRepository
    private let autosave: AutosaveCoordinator

    init(
        speech: Speech,
        repository: any SpeechRepository,
        autosave: AutosaveCoordinator,
        wordsPerMinute: Double = SpeechDurationEstimator.defaultWordsPerMinute
    ) {
        self.speech = speech
        self.repository = repository
        self.autosave = autosave
        self.wordsPerMinute = wordsPerMinute
    }

    // MARK: Salvamento

    private func mutate(_ change: (inout Speech) -> Void) {
        var copy = speech
        change(&copy)
        copy.updatedAt = Date()
        speech = copy
        Task { [autosave, weak self] in
            await autosave.note(copy)
            let state = await autosave.state
            await MainActor.run { self?.saveState = state }
        }
    }

    /// Grava imediatamente o que estiver pendente.
    func saveNow() async {
        do {
            try await repository.save(speech)
            await autosave.discardPending()
            saveState = .saved(Date())
        } catch {
            errorMessage = "Não foi possível salvar (\(error.localizedDescription)). As alterações continuam aqui."
        }
    }

    /// Grava e espera o temporizador (chamado ao sair do editor).
    func finishEditing() async {
        await autosave.note(speech)
        await autosave.flush()
        saveState = await autosave.state
    }

    func refreshSaveState() async {
        saveState = await autosave.state
    }

    // MARK: Informações

    var estimate: SpeechDurationEstimate {
        SpeechDurationEstimator.estimate(speech: speech, wordsPerMinute: wordsPerMinute)
    }

    var durationSummary: String {
        let estimated = SpeechDetailViewModel.minutesText(estimate.totalMinutes)
        if let planned = speech.plannedMinutes {
            return "\(estimated) de \(SpeechDetailViewModel.minutesText(planned)) planejados"
        }
        return "\(estimated) estimados"
    }

    var allReferences: [(reference: BibleReference, sectionTitle: String, blockID: UUID)] {
        var result: [(BibleReference, String, UUID)] = []
        for section in speech.sections {
            for block in section.blocks {
                var seen = Set<BibleReference>()
                if let reference = block.reference, block.kind == .scripture {
                    result.append((reference, section.displayTitle, block.id))
                    seen.insert(reference)
                }
                for reference in block.referencesInText where !seen.contains(reference) {
                    result.append((reference, section.displayTitle, block.id))
                }
            }
        }
        return result
    }

    var progress: Double { speech.preparationProgress }

    // MARK: Metadados

    func setTitle(_ title: String) { mutate { $0.title = title } }
    func setSubtitle(_ subtitle: String) { mutate { $0.subtitle = subtitle } }
    func setOccasion(_ occasion: String) { mutate { $0.occasion = occasion } }
    func setPrivateNotes(_ notes: String) { mutate { $0.privateNotes = notes } }
    func setStatus(_ status: SpeechStatus) { mutate { $0.status = status } }
    func toggleFavorite() { mutate { $0.isFavorite.toggle() } }

    func setPlannedMinutes(_ minutes: Double?) {
        mutate { $0.plannedMinutes = minutes }
    }

    func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { speech in
            guard !speech.tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            speech.tags.append(trimmed)
        }
    }

    func removeTag(_ tag: String) {
        mutate { $0.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame } }
    }

    // MARK: Tópicos

    @discardableResult
    func addSection(title: String = "") -> UUID {
        let number = speech.sections.count + 1
        let section = SpeechSection(
            title: title.isEmpty ? "Tópico \(number)" : title,
            blocks: [.paragraph("")]
        )
        mutate { $0.sections.append(section) }
        return section.id
    }

    func deleteSection(id: UUID) {
        mutate { $0.sections.removeAll { $0.id == id } }
    }

    func setSectionTitle(_ title: String, id: UUID) {
        mutate { speech in
            guard let index = speech.sections.firstIndex(where: { $0.id == id }) else { return }
            speech.sections[index].title = title
        }
    }

    func setSectionSubtitle(_ subtitle: String, id: UUID) {
        mutate { speech in
            guard let index = speech.sections.firstIndex(where: { $0.id == id }) else { return }
            speech.sections[index].subtitle = subtitle
        }
    }

    func setSectionNotes(_ notes: String, id: UUID) {
        mutate { speech in
            guard let index = speech.sections.firstIndex(where: { $0.id == id }) else { return }
            speech.sections[index].privateNotes = notes
        }
    }

    func toggleSectionCompleted(id: UUID) {
        mutate { speech in
            guard let index = speech.sections.firstIndex(where: { $0.id == id }) else { return }
            speech.sections[index].isCompleted.toggle()
        }
    }

    func moveSections(from source: IndexSet, to destination: Int) {
        mutate { speech in
            speech.sections.move(fromOffsets: source, toOffset: destination)
        }
    }

    @discardableResult
    func duplicateSection(id: UUID) -> UUID? {
        guard let section = speech.sections.first(where: { $0.id == id }) else { return nil }
        let copy = section.duplicated()
        mutate { speech in
            if let index = speech.sections.firstIndex(where: { $0.id == id }) {
                speech.sections.insert(copy, at: index + 1)
            } else {
                speech.sections.append(copy)
            }
        }
        return copy.id
    }

    // MARK: Blocos

    @discardableResult
    func addBlock(kind: SpeechBlockKind, toSection sectionID: UUID, after blockID: UUID? = nil) -> UUID? {
        let block = Self.makeBlock(kind: kind)
        var inserted = true
        mutate { speech in
            guard let sectionIndex = speech.sections.firstIndex(where: { $0.id == sectionID }) else {
                inserted = false
                return
            }
            if let blockID, let blockIndex = speech.sections[sectionIndex].blocks.firstIndex(where: { $0.id == blockID }) {
                speech.sections[sectionIndex].blocks.insert(block, at: blockIndex + 1)
            } else {
                speech.sections[sectionIndex].blocks.append(block)
            }
        }
        return inserted ? block.id : nil
    }

    private static func makeBlock(kind: SpeechBlockKind) -> SpeechBlock {
        switch kind {
        case .heading: return .heading("Novo tópico")
        case .subheading: return SpeechBlock(kind: .subheading, text: "Subtítulo")
        case .paragraph: return .paragraph("")
        case .quote: return SpeechBlock(kind: .quote, text: "Citação")
        case .bulletList: return .bullets([""])
        case .scripture: return .scripture(BibleReference(bookID: .john, chapter: 3, verseStart: 16), text: "…")
        case .note: return .note("Observação para mim")
        case .cue: return .cue(.pause, detail: "3")
        case .divider: return SpeechBlock(kind: .divider, text: "")
        }
    }

    func setBlockText(_ text: String, blockID: UUID) {
        mutate { speech in
            Self.updateBlock(in: &speech, blockID: blockID) { $0.text = text }
        }
    }

    func setBlockKind(_ kind: SpeechBlockKind, blockID: UUID) {
        mutate { speech in
            Self.updateBlock(in: &speech, blockID: blockID) { $0.kind = kind }
        }
    }

    func setBlockCue(_ cue: CueKind, detail: String?, blockID: UUID) {
        mutate { speech in
            Self.updateBlock(in: &speech, blockID: blockID) {
                $0.cue = cue
                $0.cueDetail = detail
            }
        }
    }

    func setBlockReference(_ reference: BibleReference, blockID: UUID) {
        mutate { speech in
            Self.updateBlock(in: &speech, blockID: blockID) { $0.reference = reference }
        }
    }

    func toggleBlockPresenterNote(blockID: UUID) {
        mutate { speech in
            Self.updateBlock(in: &speech, blockID: blockID) { $0.isPresenterNote.toggle() }
        }
    }

    func toggleBlockHighlight(blockID: UUID) {
        mutate { speech in
            Self.updateBlock(in: &speech, blockID: blockID) { $0.isHighlighted.toggle() }
        }
    }

    func deleteBlock(blockID: UUID) {
        mutate { speech in
            for index in speech.sections.indices {
                speech.sections[index].blocks.removeAll { $0.id == blockID }
            }
        }
    }

    func moveBlocks(inSection sectionID: UUID, from source: IndexSet, to destination: Int) {
        mutate { speech in
            guard let index = speech.sections.firstIndex(where: { $0.id == sectionID }) else { return }
            speech.sections[index].blocks.move(fromOffsets: source, toOffset: destination)
        }
    }

    func addBullet(_ text: String, blockID: UUID) {
        mutate { speech in
            Self.updateBlock(in: &speech, blockID: blockID) { $0.items.append(text) }
        }
    }

    func updateBullet(at index: Int, text: String, blockID: UUID) {
        mutate { speech in
            Self.updateBlock(in: &speech, blockID: blockID) {
                guard $0.items.indices.contains(index) else { return }
                $0.items[index] = text
            }
        }
    }

    func removeBullet(at index: Int, blockID: UUID) {
        mutate { speech in
            Self.updateBlock(in: &speech, blockID: blockID) {
                guard $0.items.indices.contains(index) else { return }
                $0.items.remove(at: index)
            }
        }
    }

    private static func updateBlock(
        in speech: inout Speech,
        blockID: UUID,
        change: (inout SpeechBlock) -> Void
    ) {
        for sectionIndex in speech.sections.indices {
            if let blockIndex = speech.sections[sectionIndex].blocks.firstIndex(where: { $0.id == blockID }) {
                change(&speech.sections[sectionIndex].blocks[blockIndex])
                return
            }
        }
    }

    // MARK: Fontes

    func attachSource(_ source: SourceLink) {
        mutate { speech in
            guard !speech.sources.contains(where: { $0.url == source.url && $0.title == source.title }) else { return }
            speech.sources.append(source)
        }
    }

    func removeSource(id: UUID) {
        mutate { $0.sources.removeAll { $0.id == id } }
    }
}

private extension SpeechSection {
    /// Cópia com identificadores novos (para duplicar um tópico).
    func duplicated() -> SpeechSection {
        SpeechSection(
            title: title,
            subtitle: subtitle,
            isCompleted: false,
            plannedMinutes: plannedMinutes,
            privateNotes: privateNotes,
            blocks: blocks.map { $0.duplicated() },
            tags: tags
        )
    }
}

private extension SpeechBlock {
    func duplicated() -> SpeechBlock {
        SpeechBlock(
            kind: kind,
            text: text,
            items: items,
            reference: reference,
            cue: cue,
            cueDetail: cueDetail,
            isPresenterNote: isPresenterNote,
            isHighlighted: isHighlighted,
            sources: sources
        )
    }
}
