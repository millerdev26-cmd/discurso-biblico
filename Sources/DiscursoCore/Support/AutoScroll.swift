//
//  AutoScroll.swift
//  DiscursoCore
//
//  Rolagem automática do modo de proferimento.
//
//  Regras de bom senso (requisito do projeto):
//   - a velocidade é do usuário e fica em uma faixa razoável;
//   - **qualquer** interação pausa a rolagem e ela só retoma depois de um
//     tempo — nunca "briga" com o dedo do usuário;
//   - a rolagem para sozinha ao chegar ao fim do conteúdo;
//   - a rolagem nunca ultrapassa o conteúdo (sem "tempestade" de eventos);
//   - ao sair do modo de proferimento, o estado é descartado.
//
//  A matemática é pura (sem timers): quem chama informa o tempo decorrido.
//  Isso torna o comportamento previsível e testável.
//

import Foundation

/// Configuração da rolagem automática.
public struct AutoScrollConfiguration: Codable, Hashable, Sendable {
    /// Velocidade em pontos por segundo (faixa segura).
    public var pointsPerSecond: Double
    /// Espera antes de começar depois do toque em "iniciar".
    public var startDelay: Double
    /// Espera depois da última interação antes de retomar.
    public var resumeDelayAfterInteraction: Double
    /// Limite de segurança: nenhuma rolagem roda mais que isto (em minutos).
    public var maximumRunMinutes: Double

    /// Faixa permitida de velocidade.
    public static let allowedSpeedRange: ClosedRange<Double> = 6...90

    public static let `default` = AutoScrollConfiguration()

    public init(
        pointsPerSecond: Double = 22,
        startDelay: Double = 3,
        resumeDelayAfterInteraction: Double = 4,
        maximumRunMinutes: Double = 60
    ) {
        self.pointsPerSecond = pointsPerSecond
        self.startDelay = max(0, startDelay)
        self.resumeDelayAfterInteraction = max(1, resumeDelayAfterInteraction)
        self.maximumRunMinutes = min(max(maximumRunMinutes, 5), 180)
        let clamped = pointsPerSecond.clamped(to: AutoScrollConfiguration.allowedSpeedRange)
        self.pointsPerSecond = clamped
    }

    public func sanitized() -> AutoScrollConfiguration {
        AutoScrollConfiguration(
            pointsPerSecond: pointsPerSecond,
            startDelay: startDelay,
            resumeDelayAfterInteraction: resumeDelayAfterInteraction,
            maximumRunMinutes: maximumRunMinutes
        )
    }

    /// Velocidade descrita em palavras simples (rótulo da interface).
    public var speedLabel: String {
        let percentage = (pointsPerSecond - Self.allowedSpeedRange.lowerBound)
            / (Self.allowedSpeedRange.upperBound - Self.allowedSpeedRange.lowerBound)
        return "\(Int((percentage * 100).rounded()))%"
    }
}

/// Situação da rolagem automática (valor imutável, avançado por `advance`).
public struct AutoScrollState: Hashable, Sendable {
    /// Altura total do conteúdo, em pontos.
    public var contentHeight: Double
    /// Posição atual, em pontos (0 = topo).
    public var offset: Double
    /// `true` quando a rolagem está ativa (mesmo que momentaneamente pausada).
    public var isEnabled: Bool
    /// Enquanto este instante não passar, a rolagem fica pausada.
    public var pausedUntil: Date?
    /// Instante em que a rolagem foi iniciada (para o limite de segurança).
    public var startedAt: Date?
    /// Tempo acumulado em execução, em segundos (exclui pausas).
    public var accumulatedRunSeconds: Double
    /// `true` quando chegou ao fim do conteúdo.
    public var reachedEnd: Bool

    public init(
        contentHeight: Double = 0,
        offset: Double = 0,
        isEnabled: Bool = false,
        pausedUntil: Date? = nil,
        startedAt: Date? = nil,
        accumulatedRunSeconds: Double = 0,
        reachedEnd: Bool = false
    ) {
        self.contentHeight = max(0, contentHeight)
        self.offset = max(0, offset)
        self.isEnabled = isEnabled
        self.pausedUntil = pausedUntil
        self.startedAt = startedAt
        self.accumulatedRunSeconds = max(0, accumulatedRunSeconds)
        self.reachedEnd = reachedEnd
    }

    /// Máximo deslocamento possível.
    public var maximumOffset: Double { max(0, contentHeight) }

    /// Progresso (0...1).
    public var progress: Double {
        guard contentHeight > 0 else { return 0 }
        return (offset / contentHeight).clamped(to: 0...1)
    }

    /// `true` quando há uma pausa pendente de retomada.
    public var isPaused: Bool { pausedUntil != nil }
}

/// Motor da rolagem automática (sem timers; quem chama informa o tempo).
public struct AutoScrollEngine: Sendable {
    public var configuration: AutoScrollConfiguration

    public init(configuration: AutoScrollConfiguration = .default) {
        self.configuration = configuration.sanitized()
    }

    /// Inicia a rolagem a partir da posição atual.
    public func start(state: inout AutoScrollState, contentHeight: Double, currentOffset: Double, at now: Date) {
        state.contentHeight = max(0, contentHeight)
        state.offset = currentOffset.clamped(to: 0...state.maximumOffset)
        state.isEnabled = true
        state.reachedEnd = false
        state.startedAt = now
        state.pausedUntil = configuration.startDelay > 0 ? now.addingTimeInterval(configuration.startDelay) : nil
        state.accumulatedRunSeconds = 0
    }

    /// Interrompe definitivamente.
    public func stop(state: inout AutoScrollState) {
        state.isEnabled = false
        state.startedAt = nil
        state.pausedUntil = nil
    }

    /// Registra uma interação do usuário (pausa temporária).
    public func userInteracted(state: inout AutoScrollState, newOffset: Double? = nil, at now: Date) {
        if let newOffset {
            state.offset = newOffset.clamped(to: 0...state.maximumOffset)
        }
        guard state.isEnabled else { return }
        state.pausedUntil = now.addingTimeInterval(configuration.resumeDelayAfterInteraction)
    }

    /// Retoma manualmente (o usuário pediu para continuar).
    public func resumeNow(state: inout AutoScrollState, at now: Date) {
        guard state.isEnabled else { return }
        state.pausedUntil = nil
    }

    /// Regras aplicadas a cada avanço.
    public enum AdvanceOutcome: Equatable, Sendable {
        /// Avançou `delta` pontos.
        case advanced(Double)
        /// Pausado por interação recente (nenhum movimento).
        case paused
        /// Desligado.
        case inactive
        /// Chegou ao fim do conteúdo (a rolagem foi desligada).
        case reachedEnd
        /// Limite de segurança de tempo atingido (a rolagem foi desligada).
        case timedOut
    }

    /// Avança a rolagem no tempo informado.
    ///
    /// - Parameters:
    ///   - state: estado atual (mutado).
    ///   - seconds: tempo desde o último avanço.
    ///   - now: instante atual.
    @discardableResult
    public func advance(
        state: inout AutoScrollState,
        by seconds: Double,
        at now: Date
    ) -> AdvanceOutcome {
        guard state.isEnabled else { return .inactive }
        guard seconds > 0 else { return .paused }

        // Pausa por interação recente (ou espera inicial)?
        if let pausedUntil = state.pausedUntil {
            if now < pausedUntil { return .paused }
            state.pausedUntil = nil
        }

        // Limite de segurança.
        state.accumulatedRunSeconds += seconds
        if state.accumulatedRunSeconds > configuration.maximumRunMinutes * 60 {
            state.isEnabled = false
            return .timedOut
        }

        let previous = state.offset
        state.offset = min(previous + configuration.pointsPerSecond * seconds, state.maximumOffset)

        if state.offset >= state.maximumOffset {
            state.reachedEnd = true
            state.isEnabled = false
            return .reachedEnd
        }
        return .advanced(state.offset - previous)
    }
}
