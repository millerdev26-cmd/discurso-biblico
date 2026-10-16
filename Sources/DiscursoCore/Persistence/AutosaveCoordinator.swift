//
//  AutosaveCoordinator.swift
//  DiscursoCore
//
//  Salvamento automático com debounce, gravação imediata e recuperação.
//
//  Enquanto o usuário digita, o editor chama `note(_:)` a cada alteração.
//  O coordenador:
//
//   1. guarda o valor pendente;
//   2. reinicia um temporizador curto (debounce);
//   3. grava uma única vez quando o usuário para de digitar;
//   4. permite `flush()` (gravar já) — usado ao sair da tela, ao entrar no
//      modo de proferimento e antes de exportar/compartilhar;
//   5. expõe o estado do último salvamento para a interface ("Salvo às 14:32").
//
//  A gravação usa o repositório injetado (arquivo atômico no dispositivo,
//  InMemory nos testes). Uma falha de gravação **não** descarta o valor
//  pendente: ele será tentado de novo no próximo `note`/`flush`.
//

import Foundation

/// Coordenador de salvamento automático de um discurso.
public actor AutosaveCoordinator {

    /// Estado do salvamento, exibido na interface.
    public enum State: Equatable, Sendable {
        case idle
        /// Alterações aguardando o temporizador.
        case pending
        /// Gravação em andamento.
        case saving
        /// Gravado com sucesso.
        case saved(Date)
        /// Falhou; o valor continua pendente.
        case failed(String, Date)
    }

    private let debounceSeconds: Double
    private let save: @Sendable (Speech) async throws -> Void

    private var pending: Speech?
    private var pendingSince: Date?
    private var timerTask: Task<Void, Never>?
    private var stateValue: State = .idle
    /// Gerações para ignorar temporizadores antigos.
    private var generation = 0

    public init(
        debounceSeconds: Double = 2.5,
        save: @escaping @Sendable (Speech) async throws -> Void
    ) {
        self.debounceSeconds = max(0.05, debounceSeconds)
        self.save = save
    }

    /// Inicializador de conveniência ligado a um repositório.
    public init(
        debounceSeconds: Double = 2.5,
        repository: any SpeechRepository
    ) {
        self.init(debounceSeconds: debounceSeconds) { speech in
            try await repository.save(speech)
        }
    }

    public var state: State { stateValue }

    /// `true` quando existe alteração ainda não gravada.
    public var hasPendingChanges: Bool { pending != nil }

    /// Registra uma alteração (reinicia o temporizador).
    public func note(_ speech: Speech) {
        pending = speech
        pendingSince = Date()
        stateValue = .pending
        generation += 1
        let currentGeneration = generation
        timerTask?.cancel()
        timerTask = Task { [debounceSeconds] in
            do {
                try await Task.sleep(nanoseconds: UInt64(debounceSeconds * 1_000_000_000))
            } catch {
                return // cancelado
            }
            await self.fire(ifGenerationMatches: currentGeneration)
        }
    }

    /// Grava imediatamente o que estiver pendente (se houver).
    public func flush() async {
        timerTask?.cancel()
        timerTask = nil
        generation += 1
        await performSave()
    }

    /// Descarta o que estiver pendente (ex.: ao descartar alterações).
    public func discardPending() {
        timerTask?.cancel()
        timerTask = nil
        generation += 1
        pending = nil
        pendingSince = nil
        stateValue = .idle
    }

    /// Aguarda o término de uma gravação em andamento (uso em testes e ao
    /// encerrar o aplicativo).
    public func waitForCompletion() async {
        await timerTask?.value
        // Dá chance para uma gravação disparada pelo temporizador terminar.
        while case .saving = stateValue {
            await Task.yield()
        }
    }

    private func fire(ifGenerationMatches generation: Int) async {
        guard generation == self.generation else { return }
        await performSave()
    }

    private func performSave() async {
        guard let speech = pending else { return }
        stateValue = .saving
        do {
            try await save(speech)
            // Só limpa se nada novo chegou durante a gravação.
            if pending?.updatedAt == speech.updatedAt {
                pending = nil
                pendingSince = nil
            }
            stateValue = .saved(Date())
        } catch {
            stateValue = .failed(error.localizedDescription, Date())
        }
    }
}
