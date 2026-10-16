//
//  AutoScrollAndSessionTests.swift
//  DiscursoCoreTests
//
//  Testes da rolagem automática (matemática pura) e da sessão de
//  proferimento, além do salvamento automático com debounce.
//

import XCTest
@testable import DiscursoCore

final class AutoScrollEngineTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEngine(
        speed: Double = 20,
        startDelay: Double = 0,
        resumeDelay: Double = 4,
        maxMinutes: Double = 60
    ) -> AutoScrollEngine {
        AutoScrollEngine(configuration: AutoScrollConfiguration(
            pointsPerSecond: speed,
            startDelay: startDelay,
            resumeDelayAfterInteraction: resumeDelay,
            maximumRunMinutes: maxMinutes
        ))
    }

    func testAvancaNaVelocidadeConfigurada() {
        let engine = makeEngine(speed: 20)
        var state = AutoScrollState()
        engine.start(state: &state, contentHeight: 1000, currentOffset: 0, at: base)

        let outcome = engine.advance(state: &state, by: 2, at: base.addingTimeInterval(2))
        XCTAssertEqual(outcome, .advanced(40))
        XCTAssertEqual(state.offset, 40, accuracy: 0.001)
        XCTAssertTrue(state.isEnabled)
    }

    func testRespeitaAtrasoInicial() {
        let engine = makeEngine(speed: 20, startDelay: 3)
        var state = AutoScrollState()
        engine.start(state: &state, contentHeight: 1000, currentOffset: 0, at: base)

        XCTAssertEqual(engine.advance(state: &state, by: 2, at: base.addingTimeInterval(2)), .paused)
        XCTAssertEqual(state.offset, 0)

        // Depois do atraso, anda normalmente.
        XCTAssertEqual(engine.advance(state: &state, by: 1, at: base.addingTimeInterval(4)), .advanced(20))
        XCTAssertEqual(state.offset, 20, accuracy: 0.001)
    }

    func testInteracaoPausaERetomaDepois() {
        let engine = makeEngine(speed: 20, resumeDelay: 4)
        var state = AutoScrollState()
        engine.start(state: &state, contentHeight: 1000, currentOffset: 0, at: base)
        _ = engine.advance(state: &state, by: 1, at: base.addingTimeInterval(1))

        // Usuário rola com o dedo para 100 pontos.
        engine.userInteracted(state: &state, newOffset: 100, at: base.addingTimeInterval(2))

        // Durante a pausa, nada se move.
        XCTAssertEqual(engine.advance(state: &state, by: 1, at: base.addingTimeInterval(3)), .paused)
        XCTAssertEqual(state.offset, 100, accuracy: 0.001)

        // Passado o tempo de retomada, volta a rolar.
        let outcome = engine.advance(state: &state, by: 1, at: base.addingTimeInterval(7))
        XCTAssertEqual(outcome, .advanced(20))
        XCTAssertEqual(state.offset, 120, accuracy: 0.001)
    }

    func testRetomadaManualIgnoraEspera() {
        let engine = makeEngine(speed: 20, resumeDelay: 10)
        var state = AutoScrollState()
        engine.start(state: &state, contentHeight: 1000, currentOffset: 0, at: base)
        engine.userInteracted(state: &state, at: base.addingTimeInterval(1))
        engine.resumeNow(state: &state, at: base.addingTimeInterval(1))
        XCTAssertEqual(engine.advance(state: &state, by: 1, at: base.addingTimeInterval(1.5)), .advanced(20))
    }

    func testParaAoChegarAoFim() {
        let engine = makeEngine(speed: 100)
        var state = AutoScrollState()
        engine.start(state: &state, contentHeight: 150, currentOffset: 0, at: base)

        let outcome = engine.advance(state: &state, by: 100, at: base.addingTimeInterval(4))
        XCTAssertEqual(outcome, .reachedEnd)
        XCTAssertEqual(state.offset, 150, accuracy: 0.001, "Nunca passa do conteúdo")
        XCTAssertFalse(state.isEnabled, "Desliga ao chegar ao fim")
        XCTAssertTrue(state.reachedEnd)
    }

    func testNaoDisparaEmCascataComTempoGrande() {
        // "Sem tempestade": um avanço gigante é um único movimento limitado.
        let engine = makeEngine(speed: 20)
        var state = AutoScrollState()
        engine.start(state: &state, contentHeight: 10_000, currentOffset: 0, at: base)
        _ = engine.advance(state: &state, by: 3600, at: base.addingTimeInterval(3600))
        XCTAssertEqual(state.offset, 10_000, accuracy: 0.001)
        XCTAssertFalse(state.isEnabled)
    }

    func testLimiteDeSegurancaDeTempo() {
        let engine = makeEngine(speed: 1, maxMinutes: 5)
        var state = AutoScrollState()
        engine.start(state: &state, contentHeight: 1_000_000, currentOffset: 0, at: base)

        var outcome: AutoScrollEngine.AdvanceOutcome = .paused
        var now = base
        for _ in 0..<400 {
            now = now.addingTimeInterval(1)
            outcome = engine.advance(state: &state, by: 1, at: now)
            if outcome == .timedOut { break }
        }
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertFalse(state.isEnabled)
    }

    func testDesligadoNaoAvanca() {
        let engine = makeEngine()
        var state = AutoScrollState()
        engine.start(state: &state, contentHeight: 100, currentOffset: 0, at: base)
        engine.stop(state: &state)
        XCTAssertEqual(engine.advance(state: &state, by: 1, at: base.addingTimeInterval(1)), .inactive)
        XCTAssertEqual(state.offset, 0)
    }

    func testProgressoEClampDeConfiguracao() {
        var state = AutoScrollState(contentHeight: 200, offset: 50)
        XCTAssertEqual(state.progress, 0.25, accuracy: 0.001)

        let config = AutoScrollConfiguration(pointsPerSecond: 1000, resumeDelayAfterInteraction: 0, maximumRunMinutes: 1)
        XCTAssertEqual(config.pointsPerSecond, AutoScrollConfiguration.allowedSpeedRange.upperBound)
        XCTAssertGreaterThanOrEqual(config.resumeDelayAfterInteraction, 1)
        XCTAssertGreaterThanOrEqual(config.maximumRunMinutes, 5)
        state.offset = 999
        // O estado guarda o offset recebido; o clamp de posição é feito pelo motor.
        state = AutoScrollState(contentHeight: 200, offset: 999)
        XCTAssertEqual(state.progress, 1, accuracy: 0.001)
    }
}

final class PresentationSessionTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testNavegaEntreTopicosRespeitandoLimites() {
        var session = PresentationSession(speechID: UUID())
        XCTAssertFalse(session.previous(sectionCount: 3), "Já está no primeiro")
        XCTAssertTrue(session.next(sectionCount: 3))
        XCTAssertEqual(session.sectionIndex, 1)
        XCTAssertTrue(session.next(sectionCount: 3))
        XCTAssertEqual(session.sectionIndex, 2)
        XCTAssertFalse(session.next(sectionCount: 3), "Já está no último")

        session.go(toSection: 99, sectionCount: 3)
        XCTAssertEqual(session.sectionIndex, 2)
        session.go(toSection: -5, sectionCount: 3)
        XCTAssertEqual(session.sectionIndex, 0)
    }

    func testCronometroAcumulaPausas() {
        var session = PresentationSession(speechID: UUID())
        session.start(at: base)
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.elapsedSeconds(at: base.addingTimeInterval(90)), 90, accuracy: 0.001)

        session.pause(at: base.addingTimeInterval(120))
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.elapsedSeconds(at: base.addingTimeInterval(200)), 120, accuracy: 0.001)

        session.start(at: base.addingTimeInterval(300))
        XCTAssertEqual(session.elapsedSeconds(at: base.addingTimeInterval(330)), 150, accuracy: 0.001)
        XCTAssertEqual(session.elapsedDescription(at: base.addingTimeInterval(330)), "2:30")
    }

    func testPosicaoDeRetomadaUsaATopicoAtual() {
        let speech = SpeechFactory.makeSpeech()
        var session = PresentationSession(speechID: speech.id)
        session.go(toSection: 1, sectionCount: speech.sections.count)
        let position = session.readingPosition(in: speech, at: base)
        XCTAssertEqual(position.sectionID, speech.sections[1].id)
        XCTAssertEqual(position.sectionIndex, 1)
        XCTAssertEqual(position.resolvedSectionIndex(in: speech), 1)
        XCTAssertEqual(session.currentSectionTitle(in: speech), speech.sections[1].displayTitle)
    }

    func testProgressoDaSessao() {
        var session = PresentationSession(speechID: UUID())
        session.go(toSection: 0, sectionCount: 4)
        XCTAssertEqual(session.progress(sectionCount: 4), 0, accuracy: 0.001)
        session.go(toSection: 3, sectionCount: 4)
        XCTAssertEqual(session.progress(sectionCount: 4), 1, accuracy: 0.001)
    }
}

final class AutosaveCoordinatorTests: XCTestCase {

    private func makeSpeech(_ title: String, updatedAt: Date = Date()) -> Speech {
        var speech = SpeechFactory.makeSpeech(title: title)
        speech.updatedAt = updatedAt
        return speech
    }

    func testAgrupaAlteracoesEmUmaGravacao() async throws {
        let repository = InMemorySpeechRepository()
        let coordinator = AutosaveCoordinator(debounceSeconds: 0.15, repository: repository)

        var speech = makeSpeech("Rascunho")
        await coordinator.note(speech)
        speech.title = "Rascunho 2"
        await coordinator.note(speech)
        speech.title = "Rascunho 3"
        await coordinator.note(speech)

        try await Task.sleep(nanoseconds: 500_000_000)
        await coordinator.waitForCompletion()

        let stored = try await repository.loadAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.title, "Rascunho 3", "Só a última versão deve ser gravada")

        let finalState = await coordinator.state
        if case .saved = finalState {
            // ok
        } else {
            XCTFail("Estado esperado: saved, obtido \(finalState)")
        }
        let stillPending = await coordinator.hasPendingChanges
        XCTAssertFalse(stillPending)
    }

    func testFlushGravaImediatamente() async throws {
        let repository = InMemorySpeechRepository()
        let coordinator = AutosaveCoordinator(debounceSeconds: 30, repository: repository)

        await coordinator.note(makeSpeech("Antes do flush"))
        await coordinator.flush()

        let stored = try await repository.loadAll()
        XCTAssertEqual(stored.first?.title, "Antes do flush")
    }

    func testFalhaMantemPendenciaParaNovaTentativa() async throws {
        actor Counter {
            var value = 0
            func increment() -> Int { value += 1; return value }
        }
        let counter = Counter()
        actor Box { var speech: Speech?; func set(_ s: Speech) { speech = s }; func get() -> Speech? { speech } }
        let box = Box()

        let coordinator = AutosaveCoordinator(debounceSeconds: 0.05) { speech in
            let attempt = await counter.increment()
            if attempt == 1 { throw DocumentStoreError.writeFailed(file: "teste", reason: "disco cheio") }
            await box.set(speech)
        }

        await coordinator.note(makeSpeech("Importante"))
        try await Task.sleep(nanoseconds: 200_000_000) // primeira tentativa falha
        let pendingAfterFailure = await coordinator.hasPendingChanges
        XCTAssertTrue(pendingAfterFailure, "Falha não descarta o valor pendente")

        await coordinator.flush() // segunda tentativa grava
        let saved = await box.get()
        XCTAssertEqual(saved?.title, "Importante")
        let stillPending = await coordinator.hasPendingChanges
        XCTAssertFalse(stillPending)
    }

    func testDescartaAlteracoesPendentes() async throws {
        let repository = InMemorySpeechRepository()
        let coordinator = AutosaveCoordinator(debounceSeconds: 30, repository: repository)
        await coordinator.note(makeSpeech("Descartado"))
        await coordinator.discardPending()
        await coordinator.flush()
        let stored = try await repository.loadAll()
        XCTAssertTrue(stored.isEmpty)
    }
}
