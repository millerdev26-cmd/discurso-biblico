//
//  LibraryItem.swift
//  DiscursoCore
//
//  Materiais importados (biblioteca pessoal): EPUB, PDF, texto, Markdown.
//

import Foundation

/// Tipo de material da biblioteca.
public enum LibraryItemKind: String, Codable, CaseIterable, Sendable {
    case epub
    case pdf
    case plainText
    case markdown
    case html
    /// Formato reconhecido mas ainda sem suporte de leitura (ex.: DOCX, JWPUB).
    case unsupported

    public var displayName: String {
        switch self {
        case .epub: return "EPUB"
        case .pdf: return "PDF"
        case .plainText: return "Texto"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        case .unsupported: return "Formato sem suporte"
        }
    }

    public var systemImageName: String {
        switch self {
        case .epub: return "book"
        case .pdf: return "doc.richtext"
        case .plainText: return "doc.plaintext"
        case .markdown: return "text.alignleft"
        case .html: return "globe"
        case .unsupported: return "questionmark.square.dashed"
        }
    }

    /// Extensões aceitas na importação.
    public static let acceptedFileExtensions: Set<String> = [
        "epub", "pdf", "txt", "text", "md", "markdown", "html", "htm"
    ]

    /// Identifica o tipo pela extensão do arquivo.
    public static func from(fileExtension: String) -> LibraryItemKind? {
        switch fileExtension.lowercased() {
        case "epub": return .epub
        case "pdf": return .pdf
        case "txt", "text": return .plainText
        case "md", "markdown": return .markdown
        case "html", "htm": return .html
        case "docx", "doc", "rtf", "odt", "jwpub", "jwlplaylist": return .unsupported
        default: return nil
        }
    }
}

/// Situação da indexação do conteúdo para pesquisa local.
public enum LibraryIndexStatus: String, Codable, Sendable {
    /// Ainda não indexado.
    case pending
    /// Indexado com sucesso.
    case indexed
    /// Falhou (arquivo corrompido, protegido etc.).
    case failed

    public var displayName: String {
        switch self {
        case .pending: return "Aguardando indexação"
        case .indexed: return "Pesquisável"
        case .failed: return "Não foi possível indexar"
        }
    }
}

/// Nota pessoal sobre um material.
public struct LibraryNote: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var locator: ReadingLocator?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        locator: ReadingLocator? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.locator = locator
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Marcador de leitura em um material.
public struct Bookmark: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var locator: ReadingLocator
    public var label: String
    public var excerpt: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        locator: ReadingLocator,
        label: String = "",
        excerpt: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.locator = locator
        self.label = label
        self.excerpt = excerpt
        self.createdAt = createdAt
    }
}

/// Destaque em um material.
public struct Highlight: Identifiable, Codable, Hashable, Sendable {

    public enum Color: String, Codable, CaseIterable, Sendable {
        case yellow
        case green
        case blue
        case pink
        case orange

        public var displayName: String {
            switch self {
            case .yellow: return "Amarelo"
            case .green: return "Verde"
            case .blue: return "Azul"
            case .pink: return "Rosa"
            case .orange: return "Laranja"
            }
        }
    }

    public var id: UUID
    public var locator: ReadingLocator
    public var text: String
    public var color: Color
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        locator: ReadingLocator,
        text: String,
        color: Color = .yellow,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.locator = locator
        self.text = text
        self.color = color
        self.note = note
        self.createdAt = createdAt
    }
}

/// Material da biblioteca pessoal.
public struct LibraryItem: Identifiable, Codable, Hashable, Sendable {

    public static let currentSchemaVersion = 1

    public var id: UUID
    public var title: String
    public var author: String?
    /// Tipo do material.
    public var kind: LibraryItemKind
    /// Nome do arquivo copiado para a área do aplicativo.
    public var fileName: String
    /// Extensão original (para exibição e exportação).
    public var fileExtension: String
    /// Tamanho em bytes.
    public var fileSize: Int64
    /// Hash do conteúdo, usado para detectar duplicados na importação.
    public var contentHash: String
    public var importedAt: Date
    public var lastOpenedAt: Date?
    /// Categoria escolhida pelo usuário (ex.: "Revistas", "Livros").
    public var category: String?
    public var tags: [String]
    public var isFavorite: Bool
    /// Situação da indexação para pesquisa local.
    public var indexStatus: LibraryIndexStatus
    /// Motivo da falha de indexação, quando houver.
    public var indexFailureReason: String?
    /// Número de capítulos (EPUB) ou páginas (PDF), quando conhecido.
    public var unitCount: Int?
    /// Última posição de leitura.
    public var lastReadPosition: LibraryReadingPosition?
    /// Notas, marcadores e destaques.
    public var notes: [LibraryNote]
    public var bookmarks: [Bookmark]
    public var highlights: [Highlight]
    /// Endereço de origem, quando o material veio de um link.
    public var sourceURL: URL?
    /// Nome original do arquivo no momento da importação.
    public var originalFileName: String?
    /// Aviso de material protegido (DRM), se detectado.
    public var isProtected: Bool
    public var schemaVersion: Int

    public init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        kind: LibraryItemKind,
        fileName: String,
        fileExtension: String,
        fileSize: Int64 = 0,
        contentHash: String = "",
        importedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        category: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        indexStatus: LibraryIndexStatus = .pending,
        indexFailureReason: String? = nil,
        unitCount: Int? = nil,
        lastReadPosition: LibraryReadingPosition? = nil,
        notes: [LibraryNote] = [],
        bookmarks: [Bookmark] = [],
        highlights: [Highlight] = [],
        sourceURL: URL? = nil,
        originalFileName: String? = nil,
        isProtected: Bool = false,
        schemaVersion: Int = LibraryItem.currentSchemaVersion
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.kind = kind
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.contentHash = contentHash
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        self.category = category
        self.tags = tags
        self.isFavorite = isFavorite
        self.indexStatus = indexStatus
        self.indexFailureReason = indexFailureReason
        self.unitCount = unitCount
        self.lastReadPosition = lastReadPosition
        self.notes = notes
        self.bookmarks = bookmarks
        self.highlights = highlights
        self.sourceURL = sourceURL
        self.originalFileName = originalFileName
        self.isProtected = isProtected
        self.schemaVersion = schemaVersion
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (originalFileName ?? fileName) : trimmed
    }

    /// Tamanho legível ("1,2 MB").
    public var readableFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: fileSize)
    }

    /// Progresso de leitura (0...1) para a lista da biblioteca.
    public var readingProgress: Double? {
        guard let position = lastReadPosition, let unitCount, unitCount > 0 else { return nil }
        let raw = (Double(position.unitIndex) + position.fractionInsideUnit) / Double(unitCount)
        return raw.clamped(to: 0...1)
    }

    /// `true` quando o material é pesquisável localmente.
    public var isSearchable: Bool { indexStatus == .indexed }

    /// `true` quando o material pode ser aberto no leitor interno.
    public var isReadableInsideApp: Bool {
        switch kind {
        case .epub, .pdf, .plainText, .markdown, .html: return true
        case .unsupported: return false
        }
    }
}
