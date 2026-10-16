//
//  Speech.swift
//  DiscursoCore
//
//  Modelo de dados de um discurso.
//
//  O discurso **não** é um bloco único de texto: ele é composto de seções e,
//  dentro delas, de blocos estruturados. Isso é o que permite navegar por
//  tópicos, associar fontes a parágrafos, ocultar notas do apresentador,
//  estimar a duração e personalizar o modo de proferimento.
//
//  O modelo é versionado (`schemaVersion`) e extensível: campos novos podem
//  ser adicionados com valores padrão, e campos desconhecidos de versões
//  futuras não impedem a leitura (ver `SpeechCoding`).
//

import Foundation

/// Estado de preparação do discurso.
public enum SpeechStatus: String, Codable, CaseIterable, Sendable {
    /// Em preparação (esboço).
    case preparing
    /// Pronto para profetizar/proferir.
    case ready
    /// Já proferido.
    case delivered
    /// Arquivado.
    case archived

    public var displayName: String {
        switch self {
        case .preparing: return "Em preparação"
        case .ready: return "Pronto"
        case .delivered: return "Proferido"
        case .archived: return "Arquivado"
        }
    }
}

/// Pasta (categoria) para organizar discursos.
public struct SpeechFolder: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    /// Ordem manual dentro da pasta pai.
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortIndex = sortIndex
    }
}

/// Um discurso bíblico completo.
public struct Speech: Identifiable, Codable, Hashable, Sendable {

    /// Versão atual do esquema gravado em disco.
    public static let currentSchemaVersion = 1

    // MARK: Identificação

    public var id: UUID
    public var title: String
    public var subtitle: String
    /// Ocasião (ex.: "Reunião de serviço", "Discurso público").
    public var occasion: String
    public var tags: [String]
    public var folderID: UUID?

    // MARK: Datas e duração

    public var createdAt: Date
    public var updatedAt: Date
    /// Duração planejada em minutos.
    public var plannedMinutes: Double?

    // MARK: Conteúdo

    public var sections: [SpeechSection]
    /// Notas privadas do discurso inteiro (nunca exibidas por padrão).
    public var privateNotes: String

    // MARK: Organização e apresentação

    public var status: SpeechStatus
    public var isFavorite: Bool
    public var presentation: PresentationPreferences
    public var lastReadPosition: ReadingPosition?
    /// Fontes de pesquisa associadas ao discurso inteiro.
    public var sources: [SourceLink]

    /// Versão do esquema em que o discurso foi gravado.
    public var schemaVersion: Int

    public init(
        id: UUID = UUID(),
        title: String = "",
        subtitle: String = "",
        occasion: String = "",
        tags: [String] = [],
        folderID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        plannedMinutes: Double? = nil,
        sections: [SpeechSection] = [],
        privateNotes: String = "",
        status: SpeechStatus = .preparing,
        isFavorite: Bool = false,
        presentation: PresentationPreferences = .default,
        lastReadPosition: ReadingPosition? = nil,
        sources: [SourceLink] = [],
        schemaVersion: Int = Speech.currentSchemaVersion
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.occasion = occasion
        self.tags = tags
        self.folderID = folderID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.plannedMinutes = plannedMinutes
        self.sections = sections
        self.privateNotes = privateNotes
        self.status = status
        self.isFavorite = isFavorite
        self.presentation = presentation
        self.lastReadPosition = lastReadPosition
        self.sources = sources
        self.schemaVersion = schemaVersion
    }

    // MARK: - Propriedades derivadas

    /// Título de exibição, com fallback para discursos ainda sem nome.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Discurso sem título" : trimmed
    }

    /// Todos os blocos de todas as seções.
    public var allBlocks: [SpeechBlock] {
        sections.flatMap(\.blocks)
    }

    /// Total de palavras do discurso (texto que será proferido).
    public var wordCount: Int {
        allBlocks.reduce(0) { $0 + PortugueseText.speakableWordCount($1.spokenText) }
    }

    /// Estimativa de duração em minutos, incluindo pausas marcadas.
    public var estimatedMinutes: Double {
        SpeechDurationEstimator.estimate(speech: self).totalMinutes
    }

    /// Diferença entre a duração planejada e a estimada (positivo = sobra).
    public var durationDeltaMinutes: Double? {
        guard let plannedMinutes else { return nil }
        return plannedMinutes - estimatedMinutes
    }

    /// Referências bíblicas na ordem de aparição, sem repetição.
    public var references: [BibleReference] {
        var seen = Set<BibleReference>()
        var result: [BibleReference] = []
        for section in sections {
            for block in section.blocks {
                if let reference = block.reference, !seen.contains(reference) {
                    seen.insert(reference)
                    result.append(reference)
                }
                for reference in BibleReferenceParser.uniqueReferences(in: block.text)
                where !seen.contains(reference) {
                    seen.insert(reference)
                    result.append(reference)
                }
            }
        }
        return result
    }

    /// Fontes associadas ao discurso inteiro ou a qualquer bloco.
    public var allSources: [SourceLink] {
        var seen = Set<UUID>()
        var result: [SourceLink] = []
        for source in sources where !seen.contains(source.id) {
            seen.insert(source.id)
            result.append(source)
        }
        for block in allBlocks {
            for source in block.sources where !seen.contains(source.id) {
                seen.insert(source.id)
                result.append(source)
            }
        }
        return result
    }

    /// Seções com o índice em que aparecem (útil para progresso e navegação).
    public var indexedSections: [(index: Int, section: SpeechSection)] {
        sections.enumerated().map { (index: $0.offset, section: $0.element) }
    }

    /// Progresso de preparação (0...1) com base nas seções concluídas.
    public var preparationProgress: Double {
        guard !sections.isEmpty else { return 0 }
        let completed = sections.filter(\.isCompleted).count
        return Double(completed) / Double(sections.count)
    }

    /// Blocos que devem aparecer no modo de proferimento.
    /// Notas do apresentador são excluídas quando `includePresenterNotes` é falso.
    public func presentationBlocks(includePresenterNotes: Bool) -> [SpeechBlock] {
        allBlocks.filter { block in
            if block.kind == .note || block.isPresenterNote {
                return includePresenterNotes
            }
            return true
        }
    }

    // MARK: - Mutações

    /// Marca o discurso como alterado (autosave depende disso).
    public mutating func touch(at date: Date = Date()) {
        updatedAt = date
    }

    /// Insere uma seção em uma posição válida.
    public mutating func insert(section: SpeechSection, at index: Int? = nil) {
        let position = min(max(index ?? sections.count, 0), sections.count)
        sections.insert(section, at: position)
        touch()
    }

    public mutating func removeSection(id: UUID) {
        sections.removeAll { $0.id == id }
        touch()
    }

    /// Move uma seção de posição (usado pelo editor ao reordenar tópicos).
    @discardableResult
    public mutating func moveSection(id: UUID, to destination: Int) -> Bool {
        guard let current = sections.firstIndex(where: { $0.id == id }) else { return false }
        let target = min(max(destination, 0), sections.count - 1)
        guard target != current else { return false }
        let section = sections.remove(at: current)
        sections.insert(section, at: target)
        touch()
        return true
    }

    /// Move uma seção para cima/baixo.
    @discardableResult
    public mutating func moveSection(id: UUID, by offset: Int) -> Bool {
        guard let current = sections.firstIndex(where: { $0.id == id }) else { return false }
        return moveSection(id: id, to: current + offset)
    }

    /// Duplica o discurso com novos identificadores (título "cópia").
    public func duplicated(newTitle: String? = nil, now: Date = Date()) -> Speech {
        var copy = self
        copy.id = UUID()
        copy.title = newTitle ?? "\(displayTitle) (cópia)"
        copy.createdAt = now
        copy.updatedAt = now
        copy.isFavorite = false
        copy.lastReadPosition = nil
        copy.status = .preparing
        copy.sections = sections.map { section in
            var newSection = section
            newSection.id = UUID()
            newSection.blocks = section.blocks.map { block in
                var newBlock = block
                newBlock.id = UUID()
                newBlock.sources = block.sources.map { source in
                    var newSource = source
                    newSource.id = UUID()
                    return newSource
                }
                return newBlock
            }
            return newSection
        }
        copy.sources = sources.map { source in
            var newSource = source
            newSource.id = UUID()
            return newSource
        }
        return copy
    }

    /// Busca textual dentro do discurso (título, seções, blocos e notas).
    ///
    /// Devolve os trechos encontrados com contexto, indicando a seção e o
    /// bloco — é o que a interface usa para levar o usuário direto ao ponto.
    public func search(_ query: String, limit: Int = 50) -> [SpeechSearchHit] {
        let needle = PortugueseText.folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        var hits: [SpeechSearchHit] = []

        func add(_ text: String, section: SpeechSection?, block: SpeechBlock?, kind: SpeechSearchHit.Field) {
            guard hits.count < limit else { return }
            let folded = FoldedText(text)
            guard let range = folded.folded.range(of: needle) else { return }
            let offset = folded.folded.distance(from: folded.folded.startIndex, to: range.lowerBound)
            hits.append(SpeechSearchHit(
                sectionID: section?.id,
                blockID: block?.id,
                sectionTitle: section?.title ?? "",
                field: kind,
                snippet: PortugueseText.snippet(in: text, aroundOffset: offset),
                offset: offset
            ))
        }

        add(displayTitle, section: nil, block: nil, kind: .title)
        for section in sections {
            add(section.title, section: section, block: nil, kind: .sectionTitle)
            add(section.privateNotes, section: section, block: nil, kind: .privateNote)
            for block in section.blocks {
                add(block.text, section: section, block: block, kind: block.isPresenterNote ? .privateNote : .body)
                for item in block.items {
                    add(item, section: section, block: block, kind: .body)
                }
                if let source = block.sources.first(where: { PortugueseText.folded($0.title).contains(needle) }) {
                    add(source.title, section: section, block: block, kind: .source)
                }
            }
        }
        add(privateNotes, section: nil, block: nil, kind: .privateNote)
        return hits
    }

    /// Reconstrói o texto completo em formato simples (usado em exportação).
    public func plainText(includePresenterNotes: Bool = true) -> String {
        SpeechTextRenderer.plainText(of: self, includePresenterNotes: includePresenterNotes)
    }
}

/// Resultado de uma busca dentro de um discurso.
public struct SpeechSearchHit: Identifiable, Hashable, Sendable {
    public enum Field: String, Codable, Sendable {
        case title
        case sectionTitle
        case body
        case privateNote
        case source

        public var displayName: String {
            switch self {
            case .title: return "Título"
            case .sectionTitle: return "Tópico"
            case .body: return "Conteúdo"
            case .privateNote: return "Nota"
            case .source: return "Fonte"
            }
        }
    }

    public var id = UUID()
    public var sectionID: UUID?
    public var blockID: UUID?
    public var sectionTitle: String
    public var field: Field
    public var snippet: String
    public var offset: Int

    public init(
        id: UUID = UUID(),
        sectionID: UUID? = nil,
        blockID: UUID? = nil,
        sectionTitle: String = "",
        field: Field,
        snippet: String,
        offset: Int
    ) {
        self.id = id
        self.sectionID = sectionID
        self.blockID = blockID
        self.sectionTitle = sectionTitle
        self.field = field
        self.snippet = snippet
        self.offset = offset
    }
}
