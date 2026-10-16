//
//  AppSettings.swift
//  DiscursoCore
//
//  Configurações do aplicativo e preferências de pesquisa.
//

import Foundation

/// Regras de acesso aplicadas aos provedores de pesquisa externa.
///
/// Os padrões já são conservadores: um único pedido por vez, intervalo mínimo
/// entre pedidos, cache local e identificação clara do aplicativo.
public struct ResearchAccessPolicy: Codable, Hashable, Sendable {
    /// Intervalo mínimo entre requisições ao mesmo servidor, em segundos.
    public var minimumRequestInterval: Double
    /// Tempo máximo de espera por resposta, em segundos.
    public var requestTimeout: Double
    /// Validade do cache de resultados, em segundos.
    public var cacheLifetime: Double
    /// Limite de resultados considerados por consulta.
    public var maximumResults: Int
    /// Identificação enviada no cabeçalho User-Agent.
    public var userAgent: String
    /// Quando `true`, usa apenas resultados em cache (modo econômico).
    public var preferCache: Bool
    /// Quando `true`, permite consultar a página pública de resultados do WOL.
    public var allowsPublicSearchPage: Bool
    /// Quando `true`, oferece links para pesquisa no site oficial (sempre
    /// disponível como alternativa quando a consulta direta não é possível).
    public var allowsOfficialLinkFallback: Bool

    public static let `default` = ResearchAccessPolicy()

    public init(
        minimumRequestInterval: Double = 4,
        requestTimeout: Double = 20,
        cacheLifetime: Double = 60 * 60 * 24,
        maximumResults: Int = 40,
        userAgent: String = AppSettings.defaultUserAgent,
        preferCache: Bool = false,
        allowsPublicSearchPage: Bool = true,
        allowsOfficialLinkFallback: Bool = true
    ) {
        self.minimumRequestInterval = minimumRequestInterval
        self.requestTimeout = requestTimeout
        self.cacheLifetime = cacheLifetime
        self.maximumResults = maximumResults
        self.userAgent = userAgent
        self.preferCache = preferCache
        self.allowsPublicSearchPage = allowsPublicSearchPage
        self.allowsOfficialLinkFallback = allowsOfficialLinkFallback
    }

    public func sanitized() -> ResearchAccessPolicy {
        var copy = self
        copy.minimumRequestInterval = minimumRequestInterval.clamped(to: 1...120)
        copy.requestTimeout = requestTimeout.clamped(to: 5...120)
        copy.cacheLifetime = cacheLifetime.clamped(to: 60...60 * 60 * 24 * 30)
        copy.maximumResults = min(max(maximumResults, 5), 100)
        if copy.userAgent.trimmingCharacters(in: .whitespaces).isEmpty {
            copy.userAgent = AppSettings.defaultUserAgent
        }
        return copy
    }
}

/// Configurações gerais do aplicativo.
public struct AppSettings: Codable, Hashable, Sendable {

    public static let currentSchemaVersion = 1

    /// Identificação enviada às fontes públicas de pesquisa.
    public static let defaultUserAgent =
        "DiscursoBiblico/1.0 (iOS; aplicativo de estudo pessoal; +https://jw.org)"

    // MARK: Leituras

    /// Ritmo de fala usado na estimativa de duração (palavras por minuto).
    public var wordsPerMinute: Double
    /// Preferências padrão do modo de proferimento.
    public var defaultPresentation: PresentationPreferences
    /// Perfil de leitura usado por último.
    public var lastUsedReadingProfileID: UUID?
    /// Etiquetas usadas recentemente (sugestões no editor).
    public var recentTags: [String]
    /// Ocasiões usadas recentemente.
    public var recentOccasions: [String]

    // MARK: Organização

    /// Último discurso aberto (usado no atalho "Continuar").
    public var lastOpenedSpeechID: UUID?
    /// Última categoria usada na biblioteca.
    public var lastLibraryCategory: String?
    /// Modo de exibição padrão da lista de discursos.
    public var preferredSpeechSort: SpeechSortOption

    // MARK: Pesquisa

    public var researchPolicy: ResearchAccessPolicy
    /// Provedores habilitados pelo usuário.
    public var enabledResearchProviderIDs: [String]

    // MARK: Privacidade e diagnóstico

    /// `true` quando o usuário já concluiu a apresentação inicial.
    public var hasCompletedOnboarding: Bool
    /// Avisos de recuperação de dados ainda não reconhecidos pelo usuário.
    public var pendingStorageWarnings: [String]
    /// Versão do esquema das configurações.
    public var schemaVersion: Int

    public static let `default` = AppSettings()

    public init(
        wordsPerMinute: Double = SpeechDurationEstimator.defaultWordsPerMinute,
        defaultPresentation: PresentationPreferences = .default,
        lastUsedReadingProfileID: UUID? = nil,
        recentTags: [String] = [],
        recentOccasions: [String] = [],
        lastOpenedSpeechID: UUID? = nil,
        lastLibraryCategory: String? = nil,
        preferredSpeechSort: SpeechSortOption = .recentlyUpdated,
        researchPolicy: ResearchAccessPolicy = .default,
        enabledResearchProviderIDs: [String] = ResearchProviderID.allDefaults,
        hasCompletedOnboarding: Bool = false,
        pendingStorageWarnings: [String] = [],
        schemaVersion: Int = AppSettings.currentSchemaVersion
    ) {
        self.wordsPerMinute = wordsPerMinute
        self.defaultPresentation = defaultPresentation
        self.lastUsedReadingProfileID = lastUsedReadingProfileID
        self.recentTags = recentTags
        self.recentOccasions = recentOccasions
        self.lastOpenedSpeechID = lastOpenedSpeechID
        self.lastLibraryCategory = lastLibraryCategory
        self.preferredSpeechSort = preferredSpeechSort
        self.researchPolicy = researchPolicy
        self.enabledResearchProviderIDs = enabledResearchProviderIDs
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.pendingStorageWarnings = pendingStorageWarnings
        self.schemaVersion = schemaVersion
    }

    public func sanitized() -> AppSettings {
        var copy = self
        copy.wordsPerMinute = (wordsPerMinute > 40 && wordsPerMinute < 400)
            ? wordsPerMinute
            : SpeechDurationEstimator.defaultWordsPerMinute
        copy.defaultPresentation = defaultPresentation.sanitized()
        copy.researchPolicy = researchPolicy.sanitized()
        copy.recentTags = Array(recentTags.prefix(40))
        copy.recentOccasions = Array(recentOccasions.prefix(40))
        if copy.enabledResearchProviderIDs.isEmpty {
            copy.enabledResearchProviderIDs = ResearchProviderID.allDefaults
        }
        return copy
    }

    /// Registra uma etiqueta/ocasião recente sem duplicar.
    public mutating func rememberTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentTags.removeAll { PortugueseText.folded($0) == PortugueseText.folded(trimmed) }
        recentTags.insert(trimmed, at: 0)
        if recentTags.count > 40 { recentTags = Array(recentTags.prefix(40)) }
    }

    public mutating func rememberOccasion(_ occasion: String) {
        let trimmed = occasion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentOccasions.removeAll { PortugueseText.folded($0) == PortugueseText.folded(trimmed) }
        recentOccasions.insert(trimmed, at: 0)
        if recentOccasions.count > 40 { recentOccasions = Array(recentOccasions.prefix(40)) }
    }
}

/// Ordenação da lista de discursos.
public enum SpeechSortOption: String, Codable, CaseIterable, Sendable {
    case recentlyUpdated
    case recentlyCreated
    case title
    case plannedDuration
    case preparation

    public var displayName: String {
        switch self {
        case .recentlyUpdated: return "Editados recentemente"
        case .recentlyCreated: return "Criados recentemente"
        case .title: return "Título (A–Z)"
        case .plannedDuration: return "Duração"
        case .preparation: return "Preparação"
        }
    }
}

/// Identificadores dos provedores de pesquisa.
public enum ResearchProviderID {
    public static let localLibrary = "local.library"
    public static let scripture = "local.scripture"
    public static let wolPublicSearch = "wol.public.search"
    public static let jwOrgOfficialLink = "jworg.official.link"
    public static let savedResearch = "local.saved"

    /// Provedores habilitados por padrão.
    public static let allDefaults = [localLibrary, scripture, wolPublicSearch, jwOrgOfficialLink, savedResearch]
}
