//
//  EPUBModels.swift
//  DiscursoCore
//
//  Modelos do leitor EPUB.
//
//  O EPUB é um pacote ZIP com XML por dentro. A implementação aqui cobre
//  EPUB 2 (OPF + toc.ncx) e EPUB 3 (OPF + documento de navegação XHTML), com
//  tolerância a variações de metadados, sumário e estrutura, porque arquivos
//  reais variam bastante entre editores.
//
//  Proteção de conteúdo: se o pacote usa criptografia (DRM), o leitor recusa
//  abrir e explica ao usuário. Nenhum mecanismo de proteção é contornado.
//

import Foundation

/// Metadados de um livro EPUB.
public struct EPUBMetadata: Hashable, Sendable {
    public var title: String
    public var creators: [String]
    public var language: String?
    public var identifier: String?
    public var publisher: String?
    public var publishedDate: String?
    public var bookDescription: String?
    public var rights: String?
    /// Versão declarada do EPUB ("2.0", "3.0" etc.), quando informada.
    public var packageVersion: String?

    public init(
        title: String = "",
        creators: [String] = [],
        language: String? = nil,
        identifier: String? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        bookDescription: String? = nil,
        rights: String? = nil,
        packageVersion: String? = nil
    ) {
        self.title = title
        self.creators = creators
        self.language = language
        self.identifier = identifier
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.bookDescription = bookDescription
        self.rights = rights
        self.packageVersion = packageVersion
    }

    public var authorDescription: String? {
        creators.isEmpty ? nil : creators.joined(separator: ", ")
    }
}

/// Item do manifesto do EPUB.
public struct EPUBManifestItem: Hashable, Sendable {
    public var id: String
    public var href: String
    public var mediaType: String
    public var properties: [String]
    /// Caminho completo dentro do pacote.
    public var fullPath: String

    public init(id: String, href: String, mediaType: String, properties: [String], fullPath: String) {
        self.id = id
        self.href = href
        self.mediaType = mediaType
        self.properties = properties
        self.fullPath = fullPath
    }

    public var isNavigationDocument: Bool { properties.contains("nav") }
    public var isCoverImage: Bool { properties.contains("cover-image") }
    public var isXHTML: Bool {
        mediaType.contains("xhtml") || mediaType.contains("html") || fullPath.hasSuffix(".xhtml") || fullPath.hasSuffix(".html")
    }
}

/// Entrada de navegação (sumário).
public struct EPUBNavigationEntry: Hashable, Sendable {
    public var title: String
    /// Caminho completo do recurso (resolvido dentro do pacote).
    public var fullPath: String
    /// Fragmento/âncora dentro do recurso, se houver.
    public var fragment: String?
    /// Nível hierárquico (0 = raiz).
    public var level: Int
    /// Índice do capítulo na ordem de leitura, quando for possível resolver.
    public var chapterIndex: Int?

    public init(
        title: String,
        fullPath: String,
        fragment: String? = nil,
        level: Int = 0,
        chapterIndex: Int? = nil
    ) {
        self.title = title
        self.fullPath = fullPath
        self.fragment = fragment
        self.level = level
        self.chapterIndex = chapterIndex
    }
}

/// Capítulo em ordem de leitura.
public struct EPUBChapter: Hashable, Sendable {
    public var id: String
    /// Índice na ordem de leitura (spine).
    public var index: Int
    public var title: String
    public var fullPath: String
    /// Conteúdo bruto (XHTML), quando solicitado.
    public var html: String?
    /// Texto extraído.
    public var text: String
    public var headings: [HTMLHeading]
    public var wordCount: Int

    public init(
        id: String,
        index: Int,
        title: String,
        fullPath: String,
        html: String? = nil,
        text: String,
        headings: [HTMLHeading] = [],
        wordCount: Int? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.fullPath = fullPath
        self.html = html
        self.text = text
        self.headings = headings
        self.wordCount = wordCount ?? PortugueseText.speakableWordCount(text)
    }
}

/// Avisos não fatais gerados durante a leitura (arquivos incomuns etc.).
public struct EPUBDiagnostics: Hashable, Sendable {
    public var warnings: [String]
    public var usedNCXFallback: Bool
    public var generatedNavigationFromHeadings: Bool
    public var missingResources: [String]
    public var hasNavigationDocument: Bool

    public init(
        warnings: [String] = [],
        usedNCXFallback: Bool = false,
        generatedNavigationFromHeadings: Bool = false,
        missingResources: [String] = [],
        hasNavigationDocument: Bool = false
    ) {
        self.warnings = warnings
        self.usedNCXFallback = usedNCXFallback
        self.generatedNavigationFromHeadings = generatedNavigationFromHeadings
        self.missingResources = missingResources
        self.hasNavigationDocument = hasNavigationDocument
    }
}

/// Livro EPUB aberto pelo leitor.
public struct EPUBBook: Sendable {
    public var metadata: EPUBMetadata
    public var manifest: [EPUBManifestItem]
    public var chapters: [EPUBChapter]
    public var navigation: [EPUBNavigationEntry]
    public var coverImagePath: String?
    public var packagePath: String
    public var diagnostics: EPUBDiagnostics

    public init(
        metadata: EPUBMetadata,
        manifest: [EPUBManifestItem],
        chapters: [EPUBChapter],
        navigation: [EPUBNavigationEntry],
        coverImagePath: String? = nil,
        packagePath: String,
        diagnostics: EPUBDiagnostics = EPUBDiagnostics()
    ) {
        self.metadata = metadata
        self.manifest = manifest
        self.chapters = chapters
        self.navigation = navigation
        self.coverImagePath = coverImagePath
        self.packagePath = packagePath
        self.diagnostics = diagnostics
    }

    /// Total de palavras do livro.
    public var wordCount: Int { chapters.reduce(0) { $0 + $1.wordCount } }

    /// Estimativa de duração de leitura, em minutos.
    public func readingMinutes(wordsPerMinute: Double = SpeechDurationEstimator.defaultWordsPerMinute) -> Double {
        Double(wordCount) / (wordsPerMinute > 0 ? wordsPerMinute : SpeechDurationEstimator.defaultWordsPerMinute)
    }

    /// Localiza o capítulo que contém um determinado recurso.
    public func chapterIndex(forPath path: String) -> Int? {
        let normalized = EPUPPath.normalize(path)
        return chapters.firstIndex { EPUPPath.normalize($0.fullPath) == normalized }
    }
}

/// Erros de leitura de EPUB, com mensagens compreensíveis.
public enum EPUBError: LocalizedError, Equatable {
    case notAnEPUB
    case missingContainer
    case missingPackage(String)
    case emptySpine
    case protectedContent(String)
    case unreadable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .notAnEPUB:
            return "O arquivo não parece ser um EPUB válido."
        case .missingContainer:
            return "O EPUB não contém o arquivo META-INF/container.xml."
        case .missingPackage(let path):
            return "O arquivo de conteúdo do EPUB (\(path)) não foi encontrado."
        case .emptySpine:
            return "O EPUB não declara nenhum capítulo na ordem de leitura."
        case .protectedContent(let reason):
            return "Este EPUB é protegido (\(reason)). O aplicativo não remove proteções de conteúdo."
        case .unreadable(let reason):
            return "Não foi possível abrir o EPUB: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .protectedContent:
            return "Use o aplicativo oficial do fornecedor para ler este arquivo, ou importe uma versão sem proteção."
        default:
            return "Verifique se o arquivo está completo e tente importá-lo novamente."
        }
    }
}

/// Utilitários de caminho dentro de um pacote EPUB (sempre com "/").
public enum EPUPPath {

    /// Normaliza um caminho: resolve "." e "..", remove barras duplicadas.
    public static func normalize(_ path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        var components: [String] = []
        for component in decoded.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(String(component))
            }
        }
        return components.joined(separator: "/")
    }

    /// Junta o diretório base com um caminho relativo.
    public static func resolve(relativeTo baseDirectory: String, path: String) -> String {
        let trimmedPath = path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
        guard !trimmedPath.hasPrefix("/") else { return normalize(trimmedPath) }
        let combined = baseDirectory.isEmpty ? trimmedPath : "\(baseDirectory)/\(trimmedPath)"
        return normalize(combined)
    }

    /// Diretório que contém o arquivo informado.
    public static func directory(of path: String) -> String {
        let normalized = normalize(path)
        guard let lastSlash = normalized.lastIndex(of: "/") else { return "" }
        return String(normalized[normalized.startIndex..<lastSlash])
    }

    /// Separa caminho e fragmento ("cap1.xhtml#sec2").
    public static func splitFragment(_ href: String) -> (path: String, fragment: String?) {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return (String(parts[0]), nil) }
        return (String(parts[0]), String(parts[1]))
    }

    /// Sufixo do arquivo, em minúsculas.
    public static func fileExtension(of path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let dotIndex = name.lastIndex(of: ".") else { return "" }
        return String(name[name.index(after: dotIndex)...]).lowercased()
    }
}
