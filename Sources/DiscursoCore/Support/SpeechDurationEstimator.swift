//
//  SpeechDurationEstimator.swift
//  DiscursoCore
//
//  Estimativa de duração do discurso.
//
//  O cálculo é transparente e ajustável: palavras por minuto (ritmo de fala),
//  pausas marcadas com {pausa: n}, pausas implícitas nas transições e um
//  acréscimo por referência bíblica lida no modo de proferimento.
//
//  É uma estimativa, não uma medição: existe para ajudar o orador a distribuir
//  o tempo entre as seções, e a interface deixa claro que é uma aproximação.
//

import Foundation

/// Resultado da estimativa de duração de um discurso.
public struct SpeechDurationEstimate: Hashable, Sendable {
    /// Palavras consideradas (apenas conteúdo que será falado).
    public var wordCount: Int
    /// Tempo apenas de fala, em minutos.
    public var speakingMinutes: Double
    /// Tempo de pausas marcadas, em minutos.
    public var pauseMinutes: Double
    /// Acréscimo estimado para leitura de textos bíblicos, em minutos.
    public var scriptureMinutes: Double
    /// Estimativa por seção, na mesma ordem das seções do discurso.
    public var perSectionMinutes: [Double]

    /// Duração total estimada, em minutos.
    public var totalMinutes: Double {
        speakingMinutes + pauseMinutes + scriptureMinutes
    }

    /// Duração em segundos.
    public var totalSeconds: Double { totalMinutes * 60 }

    /// Texto formatado ("12 min 30 s").
    public var formatted: String {
        let totalSeconds = Int((totalMinutes * 60).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 { return "\(seconds) s" }
        if seconds == 0 { return "\(minutes) min" }
        return "\(minutes) min \(seconds) s"
    }

    /// Descrição detalhada da composição do tempo.
    public var breakdown: String {
        var parts: [String] = []
        parts.append("fala: \(Self.format(minutes: speakingMinutes))")
        if pauseMinutes > 0.01 { parts.append("pausas: \(Self.format(minutes: pauseMinutes))") }
        if scriptureMinutes > 0.01 { parts.append("textos bíblicos: \(Self.format(minutes: scriptureMinutes))") }
        return parts.joined(separator: " · ")
    }

    private static func format(minutes: Double) -> String {
        let totalSeconds = Int((minutes * 60).rounded())
        if totalSeconds < 60 { return "\(totalSeconds) s" }
        return "\(totalSeconds / 60) min \(totalSeconds % 60) s"
    }
}

public enum SpeechDurationEstimator {

    /// Ritmo padrão de fala em português em apresentação pública
    /// (palavras por minuto). É um valor conservador, adequado a discursos
    /// proferidos com calma diante de uma assistência.
    public static let defaultWordsPerMinute: Double = 128

    /// Duração padrão considerada para uma pausa sem valor explícito.
    public static let defaultPauseSeconds: Double = 1.5

    /// Tempo médio considerado para ler em voz alta um texto bíblico citado.
    public static let defaultScriptureReadSeconds: Double = 20

    /// Estimativa completa do discurso.
    public static func estimate(
        speech: Speech,
        wordsPerMinute: Double = defaultWordsPerMinute,
        scriptureReadSeconds: Double = defaultScriptureReadSeconds
    ) -> SpeechDurationEstimate {
        let safeWordsPerMinute = wordsPerMinute > 0 ? wordsPerMinute : defaultWordsPerMinute
        var perSection: [Double] = []
        var totalWords = 0
        var totalPauseSeconds: Double = 0
        var totalScriptures = 0

        for section in speech.sections {
            var sectionWords = PortugueseText.speakableWordCount(section.title)
            if !section.subtitle.isEmpty {
                sectionWords += PortugueseText.speakableWordCount(section.subtitle)
            }
            var sectionPauseSeconds: Double = 0
            var sectionScriptures = 0

            for block in section.blocks {
                if block.isPrivateContent { continue }
                switch block.kind {
                case .divider:
                    continue
                case .bulletList:
                    sectionWords += block.items.reduce(0) { $0 + PortugueseText.speakableWordCount($1) }
                case .cue:
                    // "{pausa: 3}" e blocos de indicação contam como pausa.
                    sectionPauseSeconds += Double(block.cueDetail ?? "") ?? defaultPauseSeconds
                default:
                    let plain = InlineMarkup.plainText(block.text)
                    sectionWords += PortugueseText.speakableWordCount(plain)
                    let summary = InlineMarkup.summary(of: block.text)
                    sectionPauseSeconds += summary.explicitPauseSeconds
                    sectionPauseSeconds += Double(summary.count(of: .transition)) * defaultPauseSeconds
                }
                if block.kind == .scripture || block.reference != nil {
                    sectionScriptures += 1
                } else if !block.referencesInText.isEmpty {
                    // Referência citada no meio do texto: considera meia leitura.
                    sectionScriptures += 0
                }
            }

            let speakingMinutes = Double(sectionWords) / safeWordsPerMinute
            let pauseMinutes = sectionPauseSeconds / 60
            let scriptureMinutes = Double(sectionScriptures) * scriptureReadSeconds / 60
            perSection.append(speakingMinutes + pauseMinutes + scriptureMinutes)

            totalWords += sectionWords
            totalPauseSeconds += sectionPauseSeconds
            totalScriptures += sectionScriptures
        }

        return SpeechDurationEstimate(
            wordCount: totalWords,
            speakingMinutes: Double(totalWords) / safeWordsPerMinute,
            pauseMinutes: totalPauseSeconds / 60,
            scriptureMinutes: Double(totalScriptures) * scriptureReadSeconds / 60,
            perSectionMinutes: perSection
        )
    }

    /// Estimativa de um texto simples, sem estrutura de discurso.
    public static func estimate(
        text: String,
        wordsPerMinute: Double = defaultWordsPerMinute
    ) -> Double {
        let words = PortugueseText.speakableWordCount(InlineMarkup.plainText(text))
        return Double(words) / (wordsPerMinute > 0 ? wordsPerMinute : defaultWordsPerMinute)
    }

    /// Estimativa por seção isolada.
    public static func estimate(
        section: SpeechSection,
        wordsPerMinute: Double = defaultWordsPerMinute
    ) -> Double {
        let speech = Speech(sections: [section])
        return estimate(speech: speech, wordsPerMinute: wordsPerMinute).totalMinutes
    }
}
