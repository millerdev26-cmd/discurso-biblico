//
//  SpeechReaderService.swift
//  DiscursoBiblico
//
//  Leitura em voz alta (módulo "SpeechReader").
//
//  Usa a voz do sistema (AVSpeechSynthesizer, pt-BR), 100% offline, para:
//   - ouvir o esboço e sentir o ritmo durante a preparação;
//   - revisar a pronúncia de trechos marcados.
//
//  Nada é gravado nem enviado a servidores; nenhum áudio é armazenado.
//

import AVFoundation
import DiscursoCore
import Foundation
import Observation

@MainActor
@Observable
final class SpeechReaderService: NSObject, AVSpeechSynthesizerDelegate {

    private(set) var isSpeaking = false
    private(set) var isPaused = false
    /// Bloco em leitura (quando a leitura veio do editor).
    private(set) var currentBlockID: UUID?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Lê um texto corrido (linhas separadas são lidas com uma pausa natural).
    func speak(_ text: String, identifier: UUID? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        currentBlockID = identifier

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(rate, AVSpeechUtteranceMaximumSpeechRate))
        utterance.postUtteranceDelay = 0.15
        synthesizer.speak(utterance)
    }

    func pause() {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentBlockID = nil
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = true
            self.isPaused = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isPaused = true }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isPaused = false }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.currentBlockID = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.currentBlockID = nil
        }
    }
}
