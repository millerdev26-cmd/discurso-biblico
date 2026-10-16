//
//  ReadingPosition.swift
//  DiscursoCore
//
//  Ponto de leitura (retomada exata do discurso e da biblioteca).
//
//  Guardamos **duas** referências de posição: a fração do conteúdo
//  (`scrollFraction`) e o deslocamento absoluto em pontos (`offset`). A fração
//  é a principal, porque continua válida quando o usuário muda o tamanho da
//  fonte ou a largura da coluna; o deslocamento absoluto serve de reforço
//  quando nada mudou na apresentação.
//

import Foundation

/// Ponto de leitura dentro de um discurso.
public struct ReadingPosition: Codable, Hashable, Sendable {
    /// Seção em que o usuário estava.
    public var sectionID: UUID?
    /// Bloco visível no topo da tela.
    public var blockID: UUID?
    /// Fração do conteúdo (0...1).
    public var scrollFraction: Double
    /// Deslocamento absoluto em pontos (usado quando a apresentação não mudou).
    public var offset: Double
    /// Seção correspondente (índice), útil quando a seção foi removida.
    public var sectionIndex: Int?
    /// Quando a posição foi registrada.
    public var updatedAt: Date

    public init(
        sectionID: UUID? = nil,
        blockID: UUID? = nil,
        scrollFraction: Double = 0,
        offset: Double = 0,
        sectionIndex: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.sectionID = sectionID
        self.blockID = blockID
        self.scrollFraction = scrollFraction.clamped(to: 0...1)
        self.offset = max(0, offset)
        self.sectionIndex = sectionIndex
        self.updatedAt = updatedAt
    }

    /// Descrição curta para a interface ("Tópico 3 · 42%").
    public func summary(sectionTitle: String?) -> String {
        let percentage = Int((scrollFraction * 100).rounded())
        guard let sectionTitle, !sectionTitle.isEmpty else { return "\(percentage)%" }
        return "\(sectionTitle) · \(percentage)%"
    }

    /// Resolve a seção correta mesmo quando o identificador não existe mais.
    public func resolvedSectionIndex(in speech: Speech) -> Int? {
        if let sectionID, let index = speech.sections.firstIndex(where: { $0.id == sectionID }) {
            return index
        }
        if let sectionIndex, speech.sections.indices.contains(sectionIndex) {
            return sectionIndex
        }
        return nil
    }
}

/// Ponto de leitura de um material da biblioteca (EPUB/PDF/texto).
public struct LibraryReadingPosition: Codable, Hashable, Sendable {
    /// Índice do capítulo/página (capítulos em EPUB, páginas em PDF).
    public var unitIndex: Int
    /// Fração do capítulo (0...1).
    public var fractionInsideUnit: Double
    /// Deslocamento de caractere, quando aplicável (EPUB).
    public var characterOffset: Int?
    public var updatedAt: Date

    public init(
        unitIndex: Int = 0,
        fractionInsideUnit: Double = 0,
        characterOffset: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.unitIndex = max(0, unitIndex)
        self.fractionInsideUnit = fractionInsideUnit.clamped(to: 0...1)
        self.characterOffset = characterOffset
        self.updatedAt = updatedAt
    }
}

/// Localizador genérico usado por destaques, marcadores e notas de materiais.
///
/// É intencionalmente "achatado" (todos os campos opcionais) para acomodar
/// EPUB, PDF e texto simples no mesmo tipo e evoluir sem quebrar dados antigos.
public struct ReadingLocator: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Capítulo + deslocamento de caracteres (EPUB/texto).
        case chapterOffset
        /// Página + retângulo (PDF).
        case pageRect
    }

    public var kind: Kind
    /// Índice do capítulo (EPUB/texto).
    public var chapterIndex: Int?
    /// Deslocamento de caracteres dentro do capítulo.
    public var characterOffset: Int?
    /// Comprimento do trecho, em caracteres.
    public var characterLength: Int?
    /// Página (PDF), base zero.
    public var pageIndex: Int?
    /// Retângulo normalizado na página (0...1), PDF.
    public var rectX: Double?
    public var rectY: Double?
    public var rectWidth: Double?
    public var rectHeight: Double?

    public init(
        kind: Kind,
        chapterIndex: Int? = nil,
        characterOffset: Int? = nil,
        characterLength: Int? = nil,
        pageIndex: Int? = nil,
        rectX: Double? = nil,
        rectY: Double? = nil,
        rectWidth: Double? = nil,
        rectHeight: Double? = nil
    ) {
        self.kind = kind
        self.chapterIndex = chapterIndex
        self.characterOffset = characterOffset
        self.characterLength = characterLength
        self.pageIndex = pageIndex
        self.rectX = rectX
        self.rectY = rectY
        self.rectWidth = rectWidth
        self.rectHeight = rectHeight
    }

    public static func chapter(chapterIndex: Int, offset: Int, length: Int? = nil) -> ReadingLocator {
        ReadingLocator(kind: .chapterOffset, chapterIndex: chapterIndex, characterOffset: offset, characterLength: length)
    }

    public static func page(pageIndex: Int, rect: (x: Double, y: Double, width: Double, height: Double)? = nil) -> ReadingLocator {
        ReadingLocator(
            kind: .pageRect,
            pageIndex: pageIndex,
            rectX: rect?.x,
            rectY: rect?.y,
            rectWidth: rect?.width,
            rectHeight: rect?.height
        )
    }

    /// Descrição legível ("Página 12" / "Capítulo 3").
    public func summaryText(chapterName: String? = nil) -> String {
        switch kind {
        case .chapterOffset:
            if let chapterName, !chapterName.isEmpty { return chapterName }
            return "Capítulo \((chapterIndex ?? 0) + 1)"
        case .pageRect:
            return "Página \((pageIndex ?? 0) + 1)"
        }
    }
}
