//
//  InlineMarkup.swift
//  DiscursoCore
//
//  Marcações em linha usadas dentro dos blocos de texto.
//
//  Sintaxe (simples de digitar durante a preparação):
//
//      *ênfase*                 texto com ênfase
//      {pausa}                  pausa na fala
//      {pausa: 3}               pausa de 3 segundos (usada na estimativa)
//      {tom: solene}            mudança de tom
//      {transição: próximo}     transição (aceita "transicao", com ou sem acento)
//      {lento} {rápido}         ritmo
//      {olhar}                  contato visual com a assistência
//      {nota: ...}              observação privada em linha
//
//  As referências bíblicas ("João 3:16") são reconhecidas separadamente pelo
//  `BibleReferenceParser` e aparecem como segmentos próprios.
//
//  O analisador devolve segmentos contíguos que cobrem o texto inteiro, o que
//  permite à interface renderizar tudo (incluindo destaques e botões) sem
//  remontar a string por conta própria.
//

import Foundation

/// Um trecho de texto com seus atributos de apresentação.
public struct InlineSegment: Hashable, Sendable {
    /// Texto exibido (sem as marcações).
    public var text: String
    /// Intervalo correspondente no texto **original** (com marcações).
    public var range: Range<String.Index>
    /// `true` quando o trecho vem de `*ênfase*`.
    public var isEmphasized: Bool
    /// Indicação associada ({pausa}, {tom: ...} etc.).
    public var cue: CueKind?
    /// Detalhe da indicação (ex.: "solene", "3").
    public var cueDetail: String?
    /// `true` quando o trecho é uma observação privada.
    public var isPrivateNote: Bool
    /// Referência bíblica, quando o trecho é uma referência.
    public var reference: BibleReference?

    public init(
        text: String,
        range: Range<String.Index>,
        isEmphasized: Bool = false,
        cue: CueKind? = nil,
        cueDetail: String? = nil,
        isPrivateNote: Bool = false,
        reference: BibleReference? = nil
    ) {
        self.text = text
        self.range = range
        self.isEmphasized = isEmphasized
        self.cue = cue
        self.cueDetail = cueDetail
        self.isPrivateNote = isPrivateNote
        self.reference = reference
    }

    /// `true` quando o segmento não tem nenhum atributo especial.
    public var isPlain: Bool {
        !isEmphasized && cue == nil && !isPrivateNote && reference == nil
    }
}

/// Resumo das indicações encontradas em um texto.
public struct InlineMarkupSummary: Hashable, Sendable {
    public var cueCounts: [CueKind: Int]
    public var explicitPauseSeconds: Double
    public var genre: Bool

    public init(cueCounts: [CueKind: Int] = [:], explicitPauseSeconds: Double = 0, genre: Bool = true) {
        self.cueCounts = cueCounts
        self.explicitPauseSeconds = explicitPauseSeconds
        self.genre = genre
    }

    public func count(of cue: CueKind) -> Int { cueCounts[cue] ?? 0 }
}

public enum InlineMarkup {

    /// Analisa o texto e devolve segmentos contíguos, na ordem, cobrindo tudo.
    ///
    /// - Parameter detectReferences: quando `false`, as referências bíblicas não
    ///   viram segmentos próprios (útil em textos já processados).
    public static func segments(
        in text: String,
        detectReferences: Bool = true
    ) -> [InlineSegment] {
        guard !text.isEmpty else { return [] }

        let foldedText = FoldedText(text)
        let characters = Array(foldedText.folded)
        let originalCharacters = Array(text)

        // Referências bíblicas primeiro: são os trechos "atômicos" que não
        // podem ser cortados por marcações.
        let referenceRanges: [Range<Int>] = detectReferences
            ? BibleReferenceParser.matches(in: text).compactMap { match in
                let lower = text.distance(from: text.startIndex, to: match.range.lowerBound)
                let upper = text.distance(from: text.startIndex, to: match.range.upperBound)
                guard lower < upper else { return nil }
                return lower..<upper
            }
            : []

        var segments: [InlineSegment] = []
        var buffer = ""
        var bufferStart: Int?

        func flushBuffer(upTo end: Int) {
            guard let start = bufferStart, start < end else { return }
            guard let range = foldedText.originalRange(foldedOffsets: start..<end) else { return }
            segments.append(InlineSegment(text: buffer, range: range))
            buffer = ""
            bufferStart = nil
        }

        var index = 0
        while index < characters.count {
            // Referência bíblica
            if let referenceRange = referenceRanges.first(where: { $0.lowerBound == index }) {
                flushBuffer(upTo: index)
                if let range = foldedText.originalRange(foldedOffsets: referenceRange) {
                    let matched = String(text[range])
                    let reference = BibleReferenceParser.matches(in: matched).first?.reference
                    segments.append(InlineSegment(text: matched, range: range, reference: reference))
                }
                index = referenceRange.upperBound
                continue
            }

            // Observação privada: {nota: ...}
            if characters[index] == "{", let block = matchBracedBlock(at: index, characters: characters) {
                let content = String(characters[block.contentRange])
                let keyword = content.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
                let keywordFolded = PortugueseText.folded(keyword).trimmingCharacters(in: .whitespaces)
                if keywordFolded == "nota" {
                    flushBuffer(upTo: index)
                    let noteText = content.split(separator: ":", maxSplits: 1).dropFirst().first
                        .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                    if let range = foldedText.originalRange(foldedOffsets: block.fullRange) {
                        segments.append(InlineSegment(text: noteText, range: range, isPrivateNote: true))
                    }
                    index = block.fullRange.upperBound
                    continue
                }
                if let cue = cueDescriptor(forKeyword: keywordFolded) {
                    flushBuffer(upTo: index)
                    let detail = content.split(separator: ":", maxSplits: 1).dropFirst().first
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    if let range = foldedText.originalRange(foldedOffsets: block.fullRange) {
                        segments.append(InlineSegment(
                            text: cue.displayText,
                            range: range,
                            cue: cue.kind,
                            cueDetail: (detail?.isEmpty ?? true) ? nil : detail
                        ))
                    }
                    index = block.fullRange.upperBound
                    continue
                }
                // Bloco desconhecido: tratado como texto comum.
                if bufferStart == nil { bufferStart = index }
                buffer.append(originalCharacters[index])
                index += 1
                continue
            }

            // Ênfase: *texto*
            if characters[index] == "*", let block = matchEmphasis(at: index, characters: characters) {
                flushBuffer(upTo: index)
                if let range = foldedText.originalRange(foldedOffsets: block.fullRange) {
                    segments.append(InlineSegment(
                        text: String(characters[block.contentRange]),
                        range: range,
                        isEmphasized: true
                    ))
                }
                index = block.fullRange.upperBound
                continue
            }

            if bufferStart == nil { bufferStart = index }
            buffer.append(originalCharacters[index])
            index += 1
        }

        flushBuffer(upTo: characters.count)
        return segments
    }

    /// Texto sem marcações (para indexação, exportação simples e estimativa).
    public static func plainText(_ text: String) -> String {
        guard text.contains("{") || text.contains("*") else { return text }
        let segments = segments(in: text, detectReferences: false)
        var plain = segments
            .filter { !$0.isPrivateNote }
            .map { $0.cue == nil ? $0.text : "" }
            .joined()
        // Preserva separação entre palavras quando removemos indicações.
        while plain.contains("  ") {
            plain = plain.replacingOccurrences(of: "  ", with: " ")
        }
        return plain.trimmingCharacters(in: .whitespaces)
    }

    /// Indicações encontradas no texto, com contagem e pausas explícitas.
    public static func summary(of text: String) -> InlineMarkupSummary {
        var counts: [CueKind: Int] = [:]
        var pauseSeconds: Double = 0
        var hasContent = false
        for segment in segments(in: text, detectReferences: false) {
            guard let cue = segment.cue else {
                if !segment.text.trimmingCharacters(in: .whitespaces).isEmpty { hasContent = true }
                continue
            }
            counts[cue, default: 0] += 1
            if cue == .pause {
                pauseSeconds += Double(segment.cueDetail ?? "") ?? SpeechDurationEstimator.defaultPauseSeconds
            }
            hasContent = true
        }
        return InlineMarkupSummary(cueCounts: counts, explicitPauseSeconds: pauseSeconds, genre: hasContent)
    }

    /// `true` quando o texto contém pelo menos uma marcação reconhecida.
    public static func containsMarkup(_ text: String) -> Bool {
        guard text.contains("{") || text.contains("*") else { return false }
        return segments(in: text, detectReferences: false).contains { !$0.isPlain }
    }

    // MARK: - Auxiliares

    private struct BracedBlock {
        /// Intervalo do conteúdo entre chaves.
        let contentRange: Range<Int>
        /// Intervalo incluindo as chaves.
        let fullRange: Range<Int>
    }

    private static func matchBracedBlock(at start: Int, characters: [Character]) -> BracedBlock? {
        var index = start + 1
        var depth = 1
        while index < characters.count {
            if characters[index] == "{" { depth += 1 }
            if characters[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return BracedBlock(contentRange: (start + 1)..<index, fullRange: start..<(index + 1))
                }
            }
            // Blocos muito longos provavelmente não são marcações.
            if index - start > 120 { return nil }
            index += 1
        }
        return nil
    }

    private struct EmphasisBlock {
        let contentRange: Range<Int>
        let fullRange: Range<Int>
    }

    private static func matchEmphasis(at start: Int, characters: [Character]) -> EmphasisBlock? {
        guard start + 1 < characters.count, characters[start + 1] != " " else { return nil }
        var index = start + 1
        while index < characters.count {
            if characters[index] == "*" {
                guard index > start + 1 else { return nil }
                return EmphasisBlock(contentRange: (start + 1)..<index, fullRange: start..<(index + 1))
            }
            if characters[index] == "\n" { return nil }
            index += 1
        }
        return nil
    }

    private static func cueDescriptor(forKeyword keyword: String) -> (kind: CueKind, displayText: String)? {
        switch keyword {
        case "pausa", "pause": return (.pause, "pausa")
        case "tom", "tom de voz": return (.toneChange, "tom")
        case "transicao", "transição": return (.transition, "transição")
        case "enfase", "ênfase": return (.emphasis, "ênfase")
        case "lento", "devagar", "desacelerar": return (.slowDown, "mais lento")
        case "rapido", "rápido", "acelerar": return (.speedUp, "mais rápido")
        case "olhar", "contato visual": return (.eyeContact, "olhar")
        default: return nil
        }
    }
}
