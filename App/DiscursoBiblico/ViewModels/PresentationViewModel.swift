//
//  PresentationViewModel.swift
//  DiscursoBiblico
//
//  Modo de proferimento (a prioridade do aplicativo).
//
//  Responsabilidades:
//   - montar o texto apresentado a partir do discurso (com marcações de
//     orador, destaques de referências e estilo por tema);
//   - controlar a sessão (`PresentationSession` do núcleo): cronômetro,
//     tópico atual, progresso, posição de retomada;
//   - conduzir a rolagem automática com o `AutoScrollEngine` (matemática
//     testada no núcleo): a interface apenas aplica o deslocamento;
//   - reagir a interações: qualquer toque/arrasto **pausa** a rolagem e ela
//     só volta depois do tempo configurado;
//   - guardar e retomar o ponto de leitura.
//
//  A VM não conhece UIKit: recebe relatórios de layout (altura do conteúdo,
//  largura visível, posição dos tópicos) da camada de apresentação.
//

import DiscursoCore
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class PresentationViewModel {

    // MARK: Entrada

    private(set) var speech: Speech
    private(set) var preferences: PresentationPreferences

    // MARK: Texto apresentado

    private(set) var attributedText = NSAttributedString()
    /// Regiões de cada tópico (para navegação e leitura do tópico atual).
    private(set) var sectionRanges: [NSRange] = []

    // MARK: Sessão

    private(set) var session: PresentationSession
    private(set) var statusMessage: String?
    private(set) var isPreparing = true

    /// Deslocamento desejado (o texto é rolado até aqui).
    var targetOffset: CGFloat = 0
    /// Altura do conteúdo e da janela visível (relatadas pela apresentação).
    private(set) var contentHeight: CGFloat = 0
    private(set) var viewportHeight: CGFloat = 0
    private(set) var viewportWidth: CGFloat = 0
    /// Posição vertical de cada tópico, medida após o layout.
    private(set) var sectionOffsets: [Int: CGFloat] = [:]

    /// Referência tocada (abre o painel lateral sem perder a posição).
    var requestedReference: BibleReference?
    /// `true` quando o usuário pediu para sair e a confirmação está pendente.
    var isExitConfirmationPresented = false
    /// Controles sobrepostos visíveis?
    var showsControls = false

    // MARK: Dependências

    private let repository: any SpeechRepository
    private let autosave: AutosaveCoordinator
    private var engine = AutoScrollEngine()
    /// `nonisolated(unsafe)`: o `deinit` (fora do ator principal) invalida o
    /// timer; todas as escritas continuam acontecendo na ação principal.
    nonisolated(unsafe) private var ticker: Timer?
    private var lastTick: Date?
    private var lastReportedOffset: CGFloat = 0
    private var didApplyInitialPosition = false
    private var lastAutoScrollError: String?

    // MARK: Inicialização

    init(
        speech: Speech,
        repository: any SpeechRepository,
        autosave: AutosaveCoordinator
    ) {
        self.speech = speech
        self.repository = repository
        self.autosave = autosave
        let sanitized = speech.presentation.sanitized()
        self.preferences = sanitized
        self.session = PresentationSession(
            speechID: speech.id,
            preferences: sanitized
        )
        rebuildText()
    }

    // MARK: Ciclo de vida

    /// Prepara o modo de apresentação (a sessão começa parada, aguardando o
    /// "Iniciar" — ninguém é pego de surpresa com o cronômetro andando).
    func prepare() {
        isPreparing = true
        engine = AutoScrollEngine(configuration: autoScrollConfiguration)
        var state = session.autoScroll
        state.contentHeight = maximumOffset
        state.offset = targetOffset
        state.isEnabled = false
        session.autoScroll = state
        session.isAutoScrollEnabled = false
        statusMessage = nil
        isPreparing = false
    }

    func startSession() {
        session.start()
        statusMessage = nil
    }

    func pauseSession() {
        session.pause()
        stopTicker()
        var state = session.autoScroll
        state.isEnabled = false
        session.autoScroll = state
        session.isAutoScrollEnabled = false
    }

    func toggleSession() {
        if session.isRunning {
            pauseSession()
        } else {
            startSession()
        }
    }

    // MARK: Texto

    /// Remonta o texto (usado ao entrar e quando as preferências mudam).
    func rebuildText() {
        let builder = PresentationTextBuilder(
            speech: speech,
            preferences: preferences
        )
        let result = builder.build()
        attributedText = result.attributedText
        sectionRanges = result.sectionRanges
    }

    /// Reaplica as preferências (tamanho, tema, espaçamento, colunas…).
    func updatePreferences(_ mutate: (inout PresentationPreferences) -> Void) {
        var copy = preferences
        mutate(&copy)
        let sanitized = copy.sanitized()
        guard sanitized != preferences else { return }
        preferences = sanitized
        session.preferences = sanitized
        engine = AutoScrollEngine(configuration: autoScrollConfiguration)
        var state = session.autoScroll
        state.pausedUntil = nil
        session.autoScroll = state
        rebuildText()
    }

    /// Aplica um perfil de leitura.
    func apply(profile: ReadingProfile) {
        updatePreferences { $0 = profile.preferences }
    }

    // MARK: Relatórios de layout

    func reportLayout(contentHeight: CGFloat, viewportHeight: CGFloat, viewportWidth: CGFloat) {
        self.contentHeight = contentHeight
        self.viewportHeight = viewportHeight
        self.viewportWidth = viewportWidth

        var state = session.autoScroll
        state.contentHeight = maximumOffset
        state.offset = min(state.offset, maximumOffset)
        session.autoScroll = state

        if !didApplyInitialPosition, contentHeight > 0 {
            didApplyInitialPosition = true
            applyInitialPosition()
        }
    }

    func reportSectionOffsets(_ offsets: [Int: CGFloat]) {
        sectionOffsets = offsets
    }

    var maximumOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    /// Insets horizontais calculados das preferências de largura/margem.
    var textHorizontalInset: CGFloat {
        guard viewportWidth > 0 else { return preferences.horizontalMargin }
        let columnInset = max(0, (1 - preferences.columnWidthFraction)) * viewportWidth / 2
        return preferences.horizontalMargin + columnInset
    }

    var readingFraction: Double {
        guard maximumOffset > 0 else { return 0 }
        return min(max(Double(targetOffset / maximumOffset), 0), 1)
    }

    // MARK: Navegação por tópicos

    var sectionCount: Int { speech.sections.count }

    var currentSectionIndex: Int {
        let offset = targetOffset + max(24, viewportHeight * 0.15)
        var index = 0
        for (candidate, y) in sectionOffsets.sorted(by: { $0.key < $1.key }) where y <= offset {
            index = candidate
        }
        return min(max(index, 0), max(0, sectionCount - 1))
    }

    var currentSectionTitle: String? {
        session.currentSectionTitle(in: speech) ?? speech.sections.first?.displayTitle
    }

    func goToSection(_ index: Int) {
        guard speech.sections.indices.contains(index) else { return }
        session.go(toSection: index, sectionCount: sectionCount)
        // Garante que o tópico apareça, mesmo antes de a medição existir.
        if let y = sectionOffsets[index] {
            setOffset(y)
        } else if sectionRanges.indices.contains(index) {
            requestScrollToSection(index)
        }
        // Trocar de tópico conta como interação: a rolagem automática segue a
        // política escolhida (pausar / pausar e retomar / continuar). Com a
        // rolagem desligada, apenas limpa o aviso anterior.
        if session.autoScroll.isEnabled {
            noteUserInteraction(offset: targetOffset)
        } else {
            statusMessage = nil
        }
    }

    func nextSection() {
        goToSection(currentSectionIndex + 1)
    }

    func previousSection() {
        goToSection(currentSectionIndex - 1)
    }

    /// Ponto intermediário: o representante rola de fato até o tópico.
    private(set) var pendingScrollToSection: Int?

    private func requestScrollToSection(_ index: Int) {
        pendingScrollToSection = index
    }

    func clearPendingScrollRequest() {
        pendingScrollToSection = nil
    }

    // MARK: Rolagem automática

    var isAutoScrollEnabled: Bool { session.autoScroll.isEnabled }

    var autoScrollSpeedDescription: String {
        preferences.autoScrollSpeedDescription
    }

    func toggleAutoScroll() {
        if session.autoScroll.isEnabled {
            stopAutoScroll()
        } else {
            startAutoScroll()
        }
    }

    func startAutoScroll() {
        guard maximumOffset > 0 else {
            statusMessage = "O texto é curto e cabe na tela: não é preciso rolar."
            return
        }
        var state = session.autoScroll
        state.contentHeight = maximumOffset
        state.offset = targetOffset
        engine.start(state: &state, contentHeight: maximumOffset, currentOffset: targetOffset, at: Date())
        session.autoScroll = state
        session.isAutoScrollEnabled = true
        statusMessage = nil
        if !session.isRunning { session.start() }
        startTicker()
    }

    func stopAutoScroll(reason: String? = nil) {
        var state = session.autoScroll
        engine.stop(state: &state)
        session.autoScroll = state
        session.isAutoScrollEnabled = false
        stopTicker()
        statusMessage = reason
        lastAutoScrollError = nil
    }

    func resumeAutoScrollNow() {
        var state = session.autoScroll
        engine.resumeNow(state: &state, at: Date())
        session.autoScroll = state
        statusMessage = nil
    }

    /// Chamado quando o usuário toca ou arrasta o texto.
    ///
    /// O comportamento segue `autoScrollInteractionPolicy`:
    ///   - `pause`: para de vez (o usuário retoma quando quiser);
    ///   - `pauseAndResume`: pausa e retoma depois do tempo configurado;
    ///   - `keepScrolling`: não pausa (não recomendado).
    func noteUserInteraction(offset: CGFloat) {
        lastReportedOffset = offset
        targetOffset = min(max(0, offset), maximumOffset)
        guard session.autoScroll.isEnabled else { return }

        switch preferences.autoScrollInteractionPolicy {
        case .keepScrolling:
            var state = session.autoScroll
            state.offset = targetOffset
            session.autoScroll = state
        case .pause:
            stopAutoScroll(reason: "Rolagem pausada. Toque em ▶ para continuar.")
        case .pauseAndResume:
            var state = session.autoScroll
            engine.userInteracted(state: &state, newOffset: targetOffset, at: Date())
            session.autoScroll = state
            let delay = Int(preferences.autoScrollResumeDelay.rounded())
            statusMessage = "Rolagem pausada — continua sozinha em \(delay) s."
        }
    }

    private func startTicker() {
        stopTicker()
        lastTick = nil
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        lastTick = nil
    }

    private func tick() {
        let now = Date()
        guard let previous = lastTick else {
            lastTick = now
            return
        }
        lastTick = now
        let seconds = now.timeIntervalSince(previous)

        var state = session.autoScroll
        let outcome = engine.advance(state: &state, by: seconds, at: now)
        session.autoScroll = state

        switch outcome {
        case .advanced(let delta):
            setOffset(targetOffset + CGFloat(delta))
        case .reachedEnd:
            session.isAutoScrollEnabled = false
            stopTicker()
            statusMessage = "Fim do discurso."
        case .timedOut:
            session.isAutoScrollEnabled = false
            stopTicker()
            statusMessage = "A rolagem automática parou por segurança após \(Int(engine.configuration.maximumRunMinutes)) min. Toque em ▶ para continuar."
        case .paused, .inactive:
            break
        }
    }

    // MARK: Rolagem manual

    func setOffset(_ value: CGFloat) {
        let clamped = min(max(0, value), maximumOffset)
        targetOffset = clamped
        lastReportedOffset = clamped
        var state = session.autoScroll
        state.offset = clamped
        if clamped >= maximumOffset, maximumOffset > 0 {
            state.reachedEnd = true
        }
        session.autoScroll = state
    }

    func scrollBy(_ delta: CGFloat) {
        noteUserInteraction(offset: targetOffset + delta)
    }

    /// Um "empurrão" curto para frente (usado pelos botões flutuantes).
    func nudgeForward() {
        scrollBy(max(120, viewportHeight * 0.3))
    }

    func nudgeBackward() {
        scrollBy(-max(120, viewportHeight * 0.3))
    }

    // MARK: Posição de retomada

    private func applyInitialPosition() {
        if let position = speech.lastReadPosition {
            if let index = position.resolvedSectionIndex(in: speech),
               let y = sectionOffsets[index] {
                setOffset(y)
                return
            }
            if position.offset > 0 {
                setOffset(CGFloat(position.offset))
                return
            }
            if position.scrollFraction > 0 {
                setOffset(CGFloat(position.scrollFraction) * maximumOffset)
                return
            }
            if let index = position.sectionIndex, sectionRanges.indices.contains(index) {
                requestScrollToSection(index)
            }
        }
    }

    /// Monta a posição a ser gravada no discurso.
    func currentReadingPosition() -> ReadingPosition {
        let index = currentSectionIndex
        let section = speech.sections.indices.contains(index) ? speech.sections[index] : nil
        return ReadingPosition(
            sectionID: section?.id ?? sessionSpeechSectionID(index),
            blockID: nil,
            scrollFraction: readingFraction,
            offset: Double(targetOffset),
            sectionIndex: index,
            updatedAt: Date()
        )
    }

    private func sessionSpeechSectionID(_ index: Int) -> UUID? {
        speech.sections.indices.contains(index) ? speech.sections[index].id : nil
    }

    /// Grava o ponto de leitura e as preferências no discurso (salvamento
    /// imediato ao sair da apresentação: nada se perde ao fechar).
    func persistState() async {
        var updated = speech
        updated.lastReadPosition = currentReadingPosition()
        updated.presentation = preferences
        updated.updatedAt = Date()
        speech = updated
        try? await repository.save(updated)
    }

    // MARK: Tempo

    var elapsedDescription: String { session.elapsedDescription(at: Date()) }

    var progress: Double {
        let bySection = session.progress(sectionCount: max(1, sectionCount))
        let byScroll = readingFraction
        return min(1, max(bySection, byScroll))
    }

    // MARK: Apoio

    private var autoScrollConfiguration: AutoScrollConfiguration {
        let speed = preferences.autoScrollSpeed.clamped(
            to: AutoScrollConfiguration.allowedSpeedRange
        )
        return AutoScrollConfiguration(
            pointsPerSecond: speed,
            startDelay: 1,
            resumeDelayAfterInteraction: preferences.autoScrollResumeDelay,
            maximumRunMinutes: 30
        )
    }

    deinit {
        ticker?.invalidate()
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
