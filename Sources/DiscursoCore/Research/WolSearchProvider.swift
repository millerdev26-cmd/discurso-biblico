//
//  WolSearchProvider.swift
//  DiscursoCore
//
//  Provedor de pesquisa na página pública da Biblioteca On-line (WOL).
//
//  Decisões de projeto (e limites de uso):
//   - consulta **somente** a página pública de resultados, com um pedido por
//     vez, intervalo mínimo entre pedidos e identificação no User-Agent;
//   - não contorna CAPTCHA nem qualquer desafio: se a fonte pedir verificação,
//     o provedor para e a interface oferece o link oficial como alternativa;
//   - não faz "scraping" em massa: cada pesquisa é uma consulta do usuário,
//     com cache local para evitar repetições;
//   - nada do conteúdo da página é armazenado além dos títulos, endereços e
//     metadados exibidos na própria página pública (que são links para a
//     fonte oficial).
//

import Foundation

/// Provedor de pesquisa na página pública do WOL.
public actor WolSearchProvider {

    public static let providerID = ResearchProviderID.wolPublicSearch

    /// Base oficial usada para resolver endereços relativos.
    public static let host = URL(string: "https://wol.jw.org")!

    private let fetcher: HTTPFetching
    private let policy: ResearchAccessPolicy
    private let now: @Sendable () -> Date
    private let sleeper: @Sendable (Double) async throws -> Void

    private var lastRequestAt: Date?

    public init(
        fetcher: HTTPFetching = URLSessionHTTPFetcher(),
        policy: ResearchAccessPolicy = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        sleeper: @escaping @Sendable (Double) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.fetcher = fetcher
        self.policy = policy.sanitized()
        self.now = now
        self.sleeper = sleeper
    }

    /// Endereço da página pública de resultados (formato estável verificado).
    public static func searchPageURL(for text: String, languageCode: String = "pt") -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wol.jw.org"
        components.path = "/\(languageCode)/wol/s/r5/lp-t"
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "p", value: "par")
        ]
        return components.url
    }

    /// `true` quando há uma consulta em cache válida (usado pela interface).
    public func lastRequestDate() -> Date? { lastRequestAt }
}

extension WolSearchProvider: ResearchProvider {

    public nonisolated var id: String { Self.providerID }

    public nonisolated var displayName: String { "Biblioteca On-line (resultados públicos)" }

    public nonisolated var requiresNetwork: Bool { true }

    public func search(_ query: ResearchQuery) async throws -> [ResearchResult] {
        guard policy.allowsPublicSearchPage else {
            throw ResearchProviderError.notConfigured(
                "A consulta à página pública está desativada nas configurações. Use os links oficiais."
            )
        }
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        // Intervalo mínimo entre pedidos ao mesmo servidor.
        if let lastRequestAt {
            let elapsed = now().timeIntervalSince(lastRequestAt)
            let wait = policy.minimumRequestInterval - elapsed
            if wait > 0 {
                try? await sleeper(wait)
            }
        }

        guard let url = Self.searchPageURL(for: text) else {
            throw ResearchProviderError.badResponse("endereço de pesquisa inválido")
        }

        lastRequestAt = now()
        let response = try await fetcher.fetch(HTTPFetchRequest(
            url: url,
            timeout: policy.requestTimeout,
            userAgent: policy.userAgent
        ))

        switch response.statusCode {
        case 200:
            break
        case 403:
            throw ResearchProviderError.accessBlocked("acesso negado (403)")
        case 429:
            throw ResearchProviderError.rateLimited(retryAfter: nil)
        case 500...599:
            throw ResearchProviderError.httpStatus(response.statusCode)
        default:
            throw ResearchProviderError.httpStatus(response.statusCode)
        }

        guard let html = String(data: response.data, encoding: .utf8) else {
            throw ResearchProviderError.badResponse("resposta não é texto UTF-8")
        }
        if WOLSearchResultParser.looksBlocked(html: html) {
            throw ResearchProviderError.accessBlocked("verificação solicitada pela fonte")
        }

        let parsed = WOLSearchResultParser.parse(html: html, baseURL: Self.host)
        return Self.results(from: parsed, limit: policy.maximumResults)
    }

    /// Converte os resultados da página em resultados do aplicativo.
    static func results(from parsed: [WOLSearchResult], limit: Int) -> [ResearchResult] {
        var results: [ResearchResult] = []
        for (index, result) in parsed.enumerated() {
            guard results.count < limit else { break }
            let kind = materialKind(forPublication: result.publication)
            results.append(ResearchResult(
                providerID: providerID,
                title: result.title,
                publication: result.publication,
                snippet: nil,
                url: result.url,
                kind: kind,
                score: 40 - Double(index),
                isAvailableOffline: false
            ))
            for sub in result.subResults {
                guard results.count < limit else { break }
                results.append(ResearchResult(
                    providerID: providerID,
                    title: sub.title,
                    publication: result.publication,
                    snippet: result.title,
                    url: sub.url,
                    kind: kind,
                    score: 30 - Double(index),
                    isAvailableOffline: false
                ))
            }
        }
        return results
    }

    static func materialKind(forPublication publication: String?) -> ResearchMaterialKind {
        guard let publication else { return .article }
        let folded = PortugueseText.folded(publication)
        if folded.contains("sentinela") { return .magazine }
        if folded.contains("despertai") { return .magazine }
        if folded.contains("perspicaz") || folded.contains("indice") { return .publication }
        if folded.contains("biblia") { return .book }
        return .article
    }
}
