//
//  SourceLink.swift
//  DiscursoCore
//
//  Fontes de pesquisa associadas a discursos, seções e blocos.
//

import Foundation

/// Tipo de fonte de pesquisa.
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    /// Página da web.
    case webPage
    /// Artigo ou publicação da biblioteca on-line.
    case onlinePublication
    /// Material importado na biblioteca do aplicativo (EPUB/PDF/texto).
    case localItem
    /// Referência bíblica.
    case scripture
    /// Anotação criada pelo próprio usuário.
    case note
    /// Vídeo ou áudio.
    case media

    public var displayName: String {
        switch self {
        case .webPage: return "Página da web"
        case .onlinePublication: return "Publicação on-line"
        case .localItem: return "Material da biblioteca"
        case .scripture: return "Texto bíblico"
        case .note: return "Anotação"
        case .media: return "Vídeo/áudio"
        }
    }

    public var systemImageName: String {
        switch self {
        case .webPage: return "globe"
        case .onlinePublication: return "books.vertical"
        case .localItem: return "doc.text"
        case .scripture: return "book.closed"
        case .note: return "note.text"
        case .media: return "play.rectangle"
        }
    }
}

/// Fonte de pesquisa registrada pelo usuário.
public struct SourceLink: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL?
    public var kind: SourceKind
    /// Publicação, revista ou livro de onde o material veio.
    public var publication: String?
    /// Trecho citado.
    public var excerpt: String?
    /// Nota pessoal sobre a fonte.
    public var note: String?
    /// Referência bíblica associada (quando `kind == .scripture`).
    public var reference: BibleReference?
    /// Material da biblioteca associado (quando `kind == .localItem`).
    public var libraryItemID: UUID?
    /// Capítulo/página do material, para reabrir no ponto exato.
    public var locator: ReadingLocator?
    /// Data da consulta/registro.
    public var accessedAt: Date
    /// Etiquetas livres.
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL? = nil,
        kind: SourceKind = .webPage,
        publication: String? = nil,
        excerpt: String? = nil,
        note: String? = nil,
        reference: BibleReference? = nil,
        libraryItemID: UUID? = nil,
        locator: ReadingLocator? = nil,
        accessedAt: Date = Date(),
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
        self.publication = publication
        self.excerpt = excerpt
        self.note = note
        self.reference = reference
        self.libraryItemID = libraryItemID
        self.locator = locator
        self.accessedAt = accessedAt
        self.tags = tags
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (url?.absoluteString ?? "Fonte sem título") : trimmed
    }

    /// Linha secundária exibida na interface.
    public var subtitle: String? {
        if let publication, !publication.isEmpty { return publication }
        if let url { return url.host }
        return nil
    }

    /// Data de consulta formatada (pt-BR).
    public var accessedAtDescription: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: accessedAt)
    }

    public static func scripture(_ reference: BibleReference) -> SourceLink {
        SourceLink(
            title: reference.displayText,
            url: reference.officialWebURL(),
            kind: .scripture,
            publication: "Bíblia",
            reference: reference
        )
    }
}
