//
//  ResearchService.swift
//  DiscursoCore
//
//  Orquestração da pesquisa: provedores, cache, histórico e situação.
//
//  A interface conversa apenas com este serviço. Ele:
//   1. consulta os provedores habilitados (em ordem de prioridade);
//   2. usa cache local do WOL quando estiver fresco (e cache antigo quando a
//      rede falhar — nunca deixa o usuário sem nada);
//   3. combina, deduplica e ordena os resultados;
//   4. registra o histórico de pesquisas (incluindo falhas);
//   5. devolve uma situação clara: carregando, com resultados, vazia,
//      sem conexão ou com erro explicativo por provedor.
//

import Foundation

/// Resultado completo de uma pesquisa.
public struct ResearchSearchOutcome: Sendable {
    public var query: String
    public var results: [ResearchResult]
    public var status: ResearchStatus
    /// Mensagens de falha por provedor (identificador → mensagem).
    public var providerErrors: [String: String]
    /// Provedores que responderam do cache local.
    public var cachedProviderIDs: [String]
    /// Provedores consultados.
    public var consultedProviderIDs: [String]

    public init(
        query: String,
        results: [ResearchResult] = [],
        status: ResearchStatus = .idle,
        providerErrors: [String: String] = [:],
        cachedProviderIDs: [String] = [],
        consultedProviderIDs: [String] = []
    ) {
        self.query = query
        self.results = results
        self.status = status
        self.providerErrors = providerErrors
        self.cachedProviderIDs = cachedProviderIDs
        self.consultedProviderIDs = consultedProviderIDs
    }
}

/// Serviço de pesquisa usado pela interface.
public actor ResearchService {

    private let providers: [any ResearchProvider]
    private let repository: (any ResearchRepository)?
    private var policy: ResearchAccessPolicy
    private let isOnline: @Sendable () async -> Bool
    private let now: @Sendable () -> Date

    public init(
        providers: [any ResearchProvider],
        repository: (any ResearchRepository)? = nil,
        policy: ResearchAccessPolicy = .default,
        isOnline: @escaping @Sendable () async -> Bool = { true },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.providers = providers
        self.repository = repository
        self.policy = policy.sanitized()
        self.isOnline = isOnline
        self.now = now
    }

    /// Cria o conjunto padrão de provedores.
    ///
    /// - Parameters:
    ///   - libraryLoader: materiais e índices locais.
    ///   - savedLoader: pesquisas salvas.
    ///   - fetcher: executor HTTP usado pelo WOL (injetável nos testes).
    ///   - wolSleeper: espera entre requisições (injetável nos testes).
    public static func standard(
        policy: ResearchAccessPolicy = .default,
        repository: (any ResearchRepository)? = nil,
        fetcher: HTTPFetching = URLSessionHTTPFetcher(),
        libraryLoader: @escaping LocalLibraryResearchProvider.Loader,
        savedLoader: @escaping SavedResearchProvider.Loader,
        isOnline: @escaping @Sendable () async -> Bool = { true },
        now: @escaping @Sendable () -> Date = { Date() },
        sleeper: @escaping @Sendable (Double) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) -> ResearchService {
        let providers: [any ResearchProvider] = [
            ScriptureResearchProvider(),
            LocalLibraryResearchProvider(loader: libraryLoader),
            SavedResearchProvider(loader: savedLoader),
            WolSearchProvider(fetcher: fetcher, policy: policy, now: now, sleeper: sleeper),
            OfficialLinkResearchProvider()
        ]
        return ResearchService(
            providers: providers,
            repository: repository,
            policy: policy,
            isOnline: isOnline,
            now: now
        )
    }

    /// Atualiza as regras de acesso (usado quando o usuário muda configurações).
    public func update(policy: ResearchAccessPolicy) {
        self.policy = policy.sanitized()
    }

    public func availableProviders() -> [(id: String, displayName: String, requiresNetwork: Bool)] {
        providers.map { (id: $0.id, displayName: $0.displayName, requiresNetwork: $0.requiresNetwork) }
    }

    /// Executa uma pesquisa.
    ///
    /// - Parameters:
    ///   - text: texto digitado.
    ///   - enabledProviderIDs: provedores habilitados pelo usuário.
    ///   - forceRefresh: ignora o cache do WOL (botão "tentar de novo").
    public func search(
        _ text: String,
        enabledProviderIDs: [String] = ResearchProviderID.allDefaults,
        limit: Int? = nil,
        forceRefresh: Bool = false
    ) async -> ResearchSearchOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ResearchSearchOutcome(query: trimmed, status: .empty)
        }

        let queryLimit = limit ?? policy.maximumResults
        let query = ResearchQuery.detectingReference(in: trimmed, limit: queryLimit)
        let enabled = Set(enabledProviderIDs)
        let selected = providers.filter { enabled.contains($0.id) }

        guard !selected.isEmpty else {
            let message = "Nenhum provedor de pesquisa está habilitado nas configurações."
            await recordHistory(query: trimmed, providerIDs: [], resultCount: 0, failureMessage: message)
            return ResearchSearchOutcome(query: trimmed, status: .failed(message))
        }

        let online = await isOnline()
        var results: [ResearchResult] = []
        var errors: [String: String] = [:]
        var consulted: [String] = []
        var cached: [String] = []

        for provider in selected {
            if provider.requiresNetwork, !online {
                errors[provider.id] = ResearchProviderError.offline.errorDescription
                continue
            }
            consulted.append(provider.id)
            do {
                let outcome = try await resultsWithCache(
                    from: provider,
                    query: query,
                    forceRefresh: forceRefresh
                )
                results.append(contentsOf: outcome.results)
                if outcome.fromCache { cached.append(provider.id) }
                if let warning = outcome.warning { errors[provider.id] = warning }
            } catch let error as ResearchProviderError {
                errors[provider.id] = error.errorDescription
            } catch {
                errors[provider.id] = error.localizedDescription
            }
        }

        // Deduplicação por endereço (ou título/provedor quando não há URL).
        var seen = Set<String>()
        var unique: [ResearchResult] = []
        for result in results {
            let key = result.url?.absoluteString
                ?? "\(result.providerID)|\(PortugueseText.folded(result.title))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(result)
        }

        unique.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        let limited = Array(unique.prefix(queryLimit))

        let status: ResearchStatus
        if !limited.isEmpty {
            status = .success
        } else if !online,
                  errors.values.contains(where: { $0 == ResearchProviderError.offline.errorDescription }) {
            status = .offline
        } else if let firstError = errors.values.first {
            status = .failed(firstError)
        } else {
            status = .empty
        }

        await recordHistory(
            query: trimmed,
            providerIDs: consulted,
            resultCount: limited.count,
            failureMessage: limited.isEmpty ? errors.values.first : nil
        )

        return ResearchSearchOutcome(
            query: trimmed,
            results: limited,
            status: status,
            providerErrors: errors,
            cachedProviderIDs: cached,
            consultedProviderIDs: consulted
        )
    }

    // MARK: - Cache

    private func cacheKey(for query: ResearchQuery, providerID: String) -> String {
        "\(providerID)|\(PortugueseText.folded(query.text))"
    }

    /// Resultados do provedor, usando o cache do repositório quando aplicável.
    ///
    /// O cache vale para provedores de rede (hoje, o WOL). Quando a consulta
    /// falha e existe cache antigo, ele é devolvido com um aviso — melhor um
    /// resultado desatualizado do que uma tela vazia.
    private func resultsWithCache(
        from provider: any ResearchProvider,
        query: ResearchQuery,
        forceRefresh: Bool
    ) async throws -> (results: [ResearchResult], fromCache: Bool, warning: String?) {
        guard provider.requiresNetwork, let repository else {
            return (try await provider.search(query), false, nil)
        }

        let key = cacheKey(for: query, providerID: provider.id)

        if !forceRefresh,
           let cached = try? await repository.cachedResults(forKey: key),
           cached.isFresh(lifetime: policy.cacheLifetime) || policy.preferCache {
            return (cached.results.map { $0.asResearchResult() }, true, nil)
        }

        do {
            let fresh = try await provider.search(query)
            let payload = fresh.map(ResearchResultPayload.init(result:))
            try? await repository.cache(
                CachedResearchResults(query: query.text, providerID: provider.id, results: payload),
                forKey: key
            )
            return (fresh, false, nil)
        } catch {
            // Falha de rede: aproveita cache antigo, se existir.
            if let stale = try? await repository.cachedResults(forKey: key), !stale.results.isEmpty {
                return (
                    stale.results.map { $0.asResearchResult() },
                    true,
                    "Não foi possível atualizar agora; foram usados resultados guardados."
                )
            }
            throw error
        }
    }

    // MARK: - Histórico

    private func recordHistory(
        query: String,
        providerIDs: [String],
        resultCount: Int,
        failureMessage: String?
    ) async {
        guard let repository else { return }
        let entry = SearchHistoryEntry(
            query: query,
            providerIDs: providerIDs,
            resultCount: resultCount,
            searchedAt: now(),
            failed: failureMessage != nil,
            failureMessage: failureMessage
        )
        try? await repository.record(entry)
    }
}
