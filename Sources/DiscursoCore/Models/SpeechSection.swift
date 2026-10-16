//
//  SpeechSection.swift
//  DiscursoCore
//
//  Seções (tópicos) e blocos de conteúdo do discurso.
//

import Foundation

/// Um tópico do discurso, com seus blocos de conteúdo.
public struct SpeechSection: Identifiable, Codable, Hashable, Sendable {

    public var id: UUID
    /// Título do tópico.
    public var title: String
    /// Subtítulo opcional (usado para subtópicos).
    public var subtitle: String
    /// Marcada como concluída durante a preparação.
    public var isCompleted: Bool
    /// Tempo previsto para esta seção, em minutos (opcional).
    public var plannedMinutes: Double?
    /// Notas privadas da seção (ocultas no modo de proferimento por padrão).
    public var privateNotes: String
    /// Blocos de conteúdo, em ordem.
    public var blocks: [SpeechBlock]
    /// Etiquetas específicas da seção.
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        title: String = "",
        subtitle: String = "",
        isCompleted: Bool = false,
        plannedMinutes: Double? = nil,
        privateNotes: String = "",
        blocks: [SpeechBlock] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isCompleted = isCompleted
        self.plannedMinutes = plannedMinutes
        self.privateNotes = privateNotes
        self.blocks = blocks
        self.tags = tags
    }

    /// Título de exibição da seção, com fallback.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Tópico sem título" : trimmed
    }

    /// Texto que será realmente proferido (exclui notas do apresentador).
    public var spokenText: String {
        var parts: [String] = [title, subtitle]
        for block in blocks where !block.isPresenterNote && block.kind != .note {
            parts.append(block.spokenText)
        }
        return parts.joined(separator: "\n")
    }

    /// Contagem de palavras faladas da seção.
    public var wordCount: Int {
        PortugueseText.speakableWordCount(spokenText)
    }

    /// Referências bíblicas da seção, na ordem, sem repetição.
    public var references: [BibleReference] {
        var seen = Set<BibleReference>()
        var result: [BibleReference] = []
        for block in blocks {
            if let reference = block.reference, !seen.contains(reference) {
                seen.insert(reference)
                result.append(reference)
            }
            for reference in BibleReferenceParser.uniqueReferences(in: block.text) where !seen.contains(reference) {
                seen.insert(reference)
                result.append(reference)
            }
        }
        return result
    }

    /// Fontes de pesquisa associadas à seção ou a seus blocos.
    public var sources: [SourceLink] {
        blocks.flatMap(\.sources)
    }

    public mutating func append(_ block: SpeechBlock) {
        blocks.append(block)
    }

    public mutating func removeBlock(id: UUID) {
        blocks.removeAll { $0.id == id }
    }

    /// Move um bloco dentro da seção.
    @discardableResult
    public mutating func moveBlock(id: UUID, to destination: Int) -> Bool {
        guard let current = blocks.firstIndex(where: { $0.id == id }) else { return false }
        let target = min(max(destination, 0), blocks.count - 1)
        guard target != current else { return false }
        let block = blocks.remove(at: current)
        blocks.insert(block, at: target)
        return true
    }
}

/// Tipo de bloco de conteúdo.
public enum SpeechBlockKind: String, Codable, CaseIterable, Sendable {
    /// Título principal dentro da seção.
    case heading
    /// Subtítulo.
    case subheading
    /// Parágrafo de texto.
    case paragraph
    /// Lista com marcadores.
    case bulletList
    /// Citação (recuo, itálico).
    case quote
    /// Referência bíblica destacada, com texto opcional.
    case scripture
    /// Nota do apresentador (oculta na apresentação por padrão).
    case note
    /// Indicação de apresentação: pausa, ênfase, mudança de tom, transição.
    case cue
    /// Separador visual entre partes do discurso.
    case divider

    public var displayName: String {
        switch self {
        case .heading: return "Título"
        case .subheading: return "Subtítulo"
        case .paragraph: return "Parágrafo"
        case .bulletList: return "Lista"
        case .quote: return "Citação"
        case .scripture: return "Texto bíblico"
        case .note: return "Nota"
        case .cue: return "Indicação"
        case .divider: return "Separador"
        }
    }

    public var systemImageName: String {
        switch self {
        case .heading: return "textformat.size.larger"
        case .subheading: return "textformat.size"
        case .paragraph: return "text.alignleft"
        case .bulletList: return "list.bullet"
        case .quote: return "text.quote"
        case .scripture: return "book"
        case .note: return "note.text"
        case .cue: return "megaphone"
        case .divider: return "minus"
        }
    }
}

/// Indicação de apresentação associada a um bloco ou trecho.
public enum CueKind: String, Codable, CaseIterable, Sendable {
    /// Pausa na fala.
    case pause
    /// Ênfase na leitura.
    case emphasis
    /// Mudança de tom.
    case toneChange
    /// Transição para o próximo ponto.
    case transition
    /// Aumentar o ritmo.
    case speedUp
    /// Diminuir o ritmo.
    case slowDown
    /// Olhar para a assistência.
    case eyeContact

    public var displayName: String {
        switch self {
        case .pause: return "Pausa"
        case .emphasis: return "Ênfase"
        case .toneChange: return "Mudança de tom"
        case .transition: return "Transição"
        case .speedUp: return "Acelerar"
        case .slowDown: return "Desacelerar"
        case .eyeContact: return "Contato visual"
        }
    }

    public var systemImageName: String {
        switch self {
        case .pause: return "pause.circle"
        case .emphasis: return "bold"
        case .toneChange: return "waveform"
        case .transition: return "arrow.right.circle"
        case .speedUp: return "forward"
        case .slowDown: return "backward"
        case .eyeContact: return "eye"
        }
    }
}

/// Um bloco de conteúdo do discurso.
///
/// Optamos por uma struct "achatada" (com campos opcionais) em vez de um enum
/// com valores associados: isso mantém a codificação simples, permite
/// compatibilidade com campos futuros e evita quebras ao adicionar novos tipos
/// de bloco. Blocos desconhecidos em versões futuras são lidos como `.paragraph`.
public struct SpeechBlock: Identifiable, Codable, Hashable, Sendable {

    public var id: UUID
    public var kind: SpeechBlockKind
    /// Texto principal. Pode conter marcações em linha (ver `InlineMarkup`).
    public var text: String
    /// Itens de lista (usado quando `kind == .bulletList`).
    public var items: [String]
    /// Referência bíblica do bloco (usada por `kind == .scripture`).
    public var reference: BibleReference?
    /// Indicação de apresentação.
    public var cue: CueKind?
    /// Texto auxiliar da indicação (ex.: "tom solene").
    public var cueDetail: String?
    /// Nota do apresentador: não aparece na apresentação por padrão.
    public var isPresenterNote: Bool
    /// Trecho marcado como importante (destacado no editor e na apresentação).
    public var isHighlighted: Bool
    /// Fontes de pesquisa associadas a este bloco.
    public var sources: [SourceLink]

    public init(
        id: UUID = UUID(),
        kind: SpeechBlockKind = .paragraph,
        text: String = "",
        items: [String] = [],
        reference: BibleReference? = nil,
        cue: CueKind? = nil,
        cueDetail: String? = nil,
        isPresenterNote: Bool = false,
        isHighlighted: Bool = false,
        sources: [SourceLink] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.items = items
        self.reference = reference
        self.cue = cue
        self.cueDetail = cueDetail
        self.isPresenterNote = isPresenterNote
        self.isHighlighted = isHighlighted
        self.sources = sources
    }

    /// `true` quando o bloco só existe para orientar o orador.
    public var isPrivateContent: Bool {
        isPresenterNote || kind == .note
    }

    /// Texto efetivamente proferido (sem marcações de formatação).
    public var spokenText: String {
        guard !isPrivateContent else { return "" }
        switch kind {
        case .divider:
            return ""
        case .bulletList:
            return items.joined(separator: "\n")
        case .cue:
            return text
        default:
            return InlineMarkup.plainText(text)
        }
    }

    /// Texto completo do bloco para exibição no editor.
    public var editorText: String {
        switch kind {
        case .bulletList:
            return items.map { "• \($0)" }.joined(separator: "\n")
        default:
            return text
        }
    }

    /// Referências bíblicas presentes no texto do bloco.
    public var referencesInText: [BibleReference] {
        BibleReferenceParser.uniqueReferences(in: text)
    }

    public static func heading(_ text: String) -> SpeechBlock {
        SpeechBlock(kind: .heading, text: text)
    }

    public static func paragraph(_ text: String) -> SpeechBlock {
        SpeechBlock(kind: .paragraph, text: text)
    }

    public static func note(_ text: String) -> SpeechBlock {
        SpeechBlock(kind: .note, text: text, isPresenterNote: true)
    }

    public static func scripture(_ reference: BibleReference, text: String = "") -> SpeechBlock {
        SpeechBlock(kind: .scripture, text: text, reference: reference)
    }

    public static func cue(_ cue: CueKind, detail: String? = nil) -> SpeechBlock {
        SpeechBlock(kind: .cue, text: cue.displayName, cue: cue, cueDetail: detail)
    }

    public static func bullets(_ items: [String]) -> SpeechBlock {
        SpeechBlock(kind: .bulletList, items: items)
    }
}
