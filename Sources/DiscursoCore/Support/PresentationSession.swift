//
//  PresentationSession.swift
//  DiscursoCore
//
//  Estado de uma sessão de proferimento (modo de apresentação).
//
//  A sessão registra navegação por tópicos, tempo de fala acumulado,
//  preferências ativas e o ponto de retomada — sem depender de UIKit.
//

import Foundation

/// Sessão de proferimento de um discurso.
public struct PresentationSession: Hashable, Sendable {
    public var speechID: UUID
    /// Índice do tópico atual.
    public private(set) var sectionIndex: Int
    /// Início da sessão (para o cronômetro).
    public private(set) var startedAt: Date?
    /// Fim da última sessão (quando pausado/encerrado).
    public private(set) var endedAt: Date?
    /// Tempo acumulado de fala, em segundos.
    public private(set) var accumulatedSeconds: Double
    /// Rolagem automática ligada?
    public var isAutoScrollEnabled: Bool
    /// Estado da rolagem automática.
    public var autoScroll: AutoScrollState
    /// Preferências em vigor nesta sessão.
    public var preferences: PresentationPreferences

    public init(
        speechID: UUID,
        sectionIndex: Int = 0,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        accumulatedSeconds: Double = 0,
        isAutoScrollEnabled: Bool = false,
        autoScroll: AutoScrollState = AutoScrollState(),
        preferences: PresentationPreferences = .default
    ) {
        self.speechID = speechID
        self.sectionIndex = max(0, sectionIndex)
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.accumulatedSeconds = max(0, accumulatedSeconds)
        self.isAutoScrollEnabled = isAutoScrollEnabled
        self.autoScroll = autoScroll
        self.preferences = preferences
    }

    /// `true` quando a sessão está em andamento.
    public var isRunning: Bool { startedAt != nil && endedAt == nil }

    /// Tempo de fala decorrido (inclui o período em andamento).
    public func elapsedSeconds(at now: Date = Date()) -> Double {
        var total = accumulatedSeconds
        if let startedAt, endedAt == nil {
            total += max(0, now.timeIntervalSince(startedAt))
        }
        return total
    }

    /// Tempo decorrido formatado ("12:34").
    public func elapsedDescription(at now: Date = Date()) -> String {
        let total = Int(elapsedSeconds(at: now).rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Ciclo de vida

    /// Começa (ou retoma) o cronômetro.
    public mutating func start(at now: Date = Date()) {
        guard startedAt == nil || endedAt != nil else { return }
        startedAt = now
        endedAt = nil
    }

    /// Pausa o cronômetro, acumulando o tempo decorrido.
    public mutating func pause(at now: Date = Date()) {
        guard let startedAt, endedAt == nil else { return }
        accumulatedSeconds += max(0, now.timeIntervalSince(startedAt))
        self.startedAt = nil
        endedAt = now
    }

    // MARK: - Navegação

    /// Vai para um tópico, respeitando os limites do discurso.
    public mutating func go(toSection index: Int, sectionCount: Int) {
        guard sectionCount > 0 else {
            sectionIndex = 0
            return
        }
        sectionIndex = index.clamped(to: 0...(sectionCount - 1))
    }

    /// Avança um tópico; devolve `false` quando já está no último.
    @discardableResult
    public mutating func next(sectionCount: Int) -> Bool {
        guard sectionIndex + 1 < sectionCount else { return false }
        sectionIndex += 1
        return true
    }

    /// Volta um tópico; devolve `false` quando já está no primeiro.
    @discardableResult
    public mutating func previous(sectionCount: Int) -> Bool {
        guard sectionIndex > 0 else { return false }
        sectionIndex -= 1
        return true
    }

    /// Nome do tópico atual, quando o discurso é conhecido.
    public func currentSectionTitle(in speech: Speech) -> String? {
        guard speech.sections.indices.contains(sectionIndex) else { return nil }
        return speech.sections[sectionIndex].displayTitle
    }

    /// Progresso pelos tópicos (0...1).
    public func progress(sectionCount: Int) -> Double {
        guard sectionCount > 1 else { return sectionCount == 1 ? 1 : 0 }
        return Double(sectionIndex) / Double(sectionCount - 1)
    }

    // MARK: - Retomada

    /// Ponto de retomada a ser gravado no discurso.
    public func readingPosition(in speech: Speech, at now: Date = Date()) -> ReadingPosition {
        let section = speech.sections.indices.contains(sectionIndex)
            ? speech.sections[sectionIndex]
            : nil
        return ReadingPosition(
            sectionID: section?.id,
            blockID: nil,
            scrollFraction: 0,
            offset: 0,
            sectionIndex: sectionIndex,
            updatedAt: now
        )
    }
}
