//
//  ResearchTests.swift
//  DiscursoCoreTests
//
//  Testes da área de pesquisa: leitura da página pública do WOL, provedores
//  locais, links oficiais, cache, histórico e situações de falha.
//
//  Todas as páginas usadas como entrada são fixtures sintéticas do próprio
//  projeto; nenhum pedido de rede é feito nos testes (o executor HTTP é
//  substituído por um dublê).
//

import XCTest
@testable import DiscursoCore

/// Executor HTTP de teste, com respostas programadas.
actor StubHTTPFetcher: HTTPFetching {

    struct Call: Sendable {
        var url: URL
        var userAgent: String
    }

    private var responses: [Result<HTTPFetchResponse, Error>]
    private(set) var calls: [Call] = []

    init(responses: [Result<HTTPFetchResponse, Error>]) {
        self.responses = responses
    }

    init(response: Result<HTTPFetchResponse, Error>) {
        self.responses = [response]
    }

    func fetch(_ request: HTTPFetchRequest) async throws -> HTTPFetchResponse {
        calls.append(Call(url: request.url, userAgent: request.userAgent))
        guard !responses.isEmpty else {
            throw ResearchProviderError.badResponse("sem respostas programadas")
        }
        let next = responses.removeFirst()
        switch next {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    func callCount() -> Int { calls.count }
}

final class WOLSearchResultParserTests: XCTestCase {

    func testLePaginaDeResultados() throws {
        let html = try Fixtures.string("wol/resultados-pesquisa.html")
        let results = WOLSearchResultParser.parse(html: html)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].title, "Oração")
        XCTAssertEqual(results[0].publication, "Estudo Perspicaz das Escrituras, Volume 2")
        XCTAssertEqual(results[0].url.absoluteString, "https://wol.jw.org/pt/wol/d/r5/lp-t/1200003543")
        XCTAssertTrue(results[0].subResults.isEmpty)

        XCTAssertEqual(results[1].title, "Oração-modelo")
        XCTAssertEqual(results[1].subResults.count, 1)
        XCTAssertEqual(results[1].subResults[0].title, "Lista por frase")
        XCTAssertEqual(results[1].subResults[0].url.absoluteString, "https://wol.jw.org/pt/wol/d/r5/lp-t/1200273879#p14")

        XCTAssertEqual(results[2].publication, "A Sentinela (edição de estudo), janeiro de 2026")
    }

    func testPaginaSemResultados() throws {
        let html = try Fixtures.string("wol/sem-resultados.html")
        XCTAssertTrue(WOLSearchResultParser.looksEmpty(html: html))
        XCTAssertTrue(WOLSearchResultParser.parse(html: html).isEmpty)
    }

    func testPaginaComDesafioEReconhecida() throws {
        let html = try Fixtures.string("wol/bloqueado.html")
        XCTAssertTrue(WOLSearchResultParser.looksBlocked(html: html))
    }

    func testNaoQuebraComMarcacaoMalformada() {
        let html = "<div class=\"resultContentTopic\"><a class=\"lnk\" href=\"/pt/wol/d/r5/lp-t/1\">Título"
        // Sem fechamento: o parser devolve o que conseguiu ou nada, sem lançar.
        _ = WOLSearchResultParser.parse(html: html)
    }
}

final class WolSearchProviderTests: XCTestCase {

    private func makeProvider(
        responses: [Result<HTTPFetchResponse, Error>],
        policy: ResearchAccessPolicy = ResearchAccessPolicy(minimumRequestInterval: 4),
        sleeperCalls: @escaping @Sendable (Double) -> Void = { _ in }
    ) -> (WolSearchProvider, StubHTTPFetcher) {
        let fetcher = StubHTTPFetcher(responses: responses)
        let provider = WolSearchProvider(
            fetcher: fetcher,
            policy: policy,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleeper: { seconds in sleeperCalls(seconds) }
        )
        return (provider, fetcher)
    }

    func testMontaEnderecoEMLeResultados() async throws {
        let html = try Fixtures.string("wol/resultados-pesquisa.html")
        let (provider, fetcher) = makeProvider(responses: [
            .success(HTTPFetchResponse(statusCode: 200, data: Data(html.utf8)))
        ])

        let results = try await provider.search(ResearchQuery(text: "oração"))
        XCTAssertEqual(results.count, 4, "3 resultados + 1 sub-resultado")
        XCTAssertEqual(results.first?.title, "Oração")
        XCTAssertEqual(results.first?.providerID, ResearchProviderID.wolPublicSearch)
        XCTAssertEqual(results.first?.kind, .publication)

        let calls = await fetcher.calls
        XCTAssertEqual(calls.count, 1)
        let components = try XCTUnwrap(URLComponents(url: calls[0].url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "wol.jw.org")
        XCTAssertEqual(components.path, "/pt/wol/s/r5/lp-t")
        XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "q", value: "oração")) ?? false)
        XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "p", value: "par")) ?? false)
        XCTAssertTrue(calls[0].userAgent.contains("DiscursoBiblico"))
    }

    func testPaginaComDesafioNaoEProcessada() async throws {
        let html = try Fixtures.string("wol/bloqueado.html")
        let (provider, _) = makeProvider(responses: [
            .success(HTTPFetchResponse(statusCode: 200, data: Data(html.utf8)))
        ])
        do {
            _ = try await provider.search(ResearchQuery(text: "oração"))
            XCTFail("Deveria lançar accessBlocked")
        } catch let error as ResearchProviderError {
            guard case .accessBlocked = error else {
                return XCTFail("Esperava accessBlocked, obteve \(error)")
            }
        }
    }

    func testErrosHTTPViramErrosTipados() async throws {
        let (forbidden, _) = makeProvider(responses: [
            .success(HTTPFetchResponse(statusCode: 403, data: Data()))
        ])
        do {
            _ = try await forbidden.search(ResearchQuery(text: "x"))
            XCTFail("Deveria lançar")
        } catch let error as ResearchProviderError {
            guard case .accessBlocked = error else { return XCTFail("Esperava accessBlocked, obteve \(error)") }
        }

        let (limited, _) = makeProvider(responses: [
            .success(HTTPFetchResponse(statusCode: 429, data: Data()))
        ])
        do {
            _ = try await limited.search(ResearchQuery(text: "x"))
            XCTFail("Deveria lançar")
        } catch let error as ResearchProviderError {
            guard case .rateLimited = error else { return XCTFail("Esperava rateLimited, obteve \(error)") }
        }
    }

    func testRespeitaIntervaloMinimoEntreRequisicoes() async throws {
        let html = try Fixtures.string("wol/resultados-pesquisa.html")
        actor Sleeper { var waits: [Double] = []; func add(_ v: Double) { waits.append(v) }; func all() -> [Double] { waits } }
        let sleeper = Sleeper()

        let fetcher = StubHTTPFetcher(responses: [
            .success(HTTPFetchResponse(statusCode: 200, data: Data(html.utf8))),
            .success(HTTPFetchResponse(statusCode: 200, data: Data(html.utf8)))
        ])
        let provider = WolSearchProvider(
            fetcher: fetcher,
            policy: ResearchAccessPolicy(minimumRequestInterval: 4),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleeper: { seconds in await sleeper.add(seconds) }
        )

        _ = try await provider.search(ResearchQuery(text: "um"))
        _ = try await provider.search(ResearchQuery(text: "dois"))

        // O relógio de teste é fixo, então o segundo pedido sempre espera.
        let waits = await sleeper.all()
        XCTAssertEqual(waits.count, 1)
        XCTAssertEqual(waits[0], 4, accuracy: 0.001)
    }

    func testPoliticaPodeDesligarAPaginaPublica() async {
        let policy = ResearchAccessPolicy(allowsPublicSearchPage: false)
        let (provider, _) = makeProvider(responses: [], policy: policy)
        do {
            _ = try await provider.search(ResearchQuery(text: "oração"))
            XCTFail("Deveria lançar notConfigured")
        } catch let error as ResearchProviderError {
            guard case .notConfigured = error else {
                return XCTFail("Esperava notConfigured, obteve \(error)")
            }
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    func testFalhaDeRedeERepassadaComoOffline() async {
        let (provider, _) = makeProvider(responses: [.failure(ResearchProviderError.offline)])
        do {
            _ = try await provider.search(ResearchQuery(text: "oração"))
            XCTFail("Deveria lançar")
        } catch let error as ResearchProviderError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }
}

final class ResearchProvidersTests: XCTestCase {

    func testProvedorDeReferenciaReconheceTexto() async throws {
        let provider = ScriptureResearchProvider()
        let results = try await provider.search(ResearchQuery.detectingReference(in: "ver João 3:16 com atenção"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].kind, .scripture)
        XCTAssertEqual(results[0].title, "João 3:16")
        XCTAssertEqual(results[0].url?.absoluteString, "https://wol.jw.org/pt/wol/b/r5/lp-t/nwt/43/3#16")
    }

    func testProvedorDeReferenciaIgnoraTextoComum() async throws {
        let provider = ScriptureResearchProvider()
        let results = try await provider.search(ResearchQuery(text: "oração e fé"))
        XCTAssertTrue(results.isEmpty)
    }

    func testProvedorDeLinksSempreOfereceAlternativa() async throws {
        let provider = OfficialLinkResearchProvider()
        let results = try await provider.search(ResearchQuery.detectingReference(in: "João 3:16"))
        XCTAssertGreaterThanOrEqual(results.count, 2)

        let scripture = try XCTUnwrap(results.first { $0.kind == .scripture })
        XCTAssertEqual(scripture.url?.host, "wol.jw.org")

        let search = try XCTUnwrap(results.first { $0.url?.host == "www.jw.org" })
        // Atenção: `URL.path` do Foundation no Linux remove a barra final;
        // por isso a verificação usa o endereço completo (estável em todas
        // as plataformas).
        XCTAssertTrue(search.url?.absoluteString.contains("/pt/busca/?") ?? false)
        XCTAssertTrue(search.url?.query?.contains("q=") ?? false)

        let wolSearch = try XCTUnwrap(results.first { $0.url?.absoluteString.contains("wol.jw.org/pt/wol/s/") ?? false })
        XCTAssertEqual(wolSearch.kind, .publication)
    }

    func testProvedorDaBibliotecaUsaIndiceLocal() async throws {
        let item = LibraryItem(
            title: "Meus esboços",
            kind: .plainText,
            fileName: "esbocos.txt",
            fileExtension: "txt",
            fileSize: 100,
            contentHash: "fnv1a64:teste",
            indexStatus: .indexed
        )
        let index = LibraryTextIndexBuilder.build(
            itemID: item.id,
            units: [(title: "Oração", text: "A oração é uma provisão amorosa. Filipenses 4:6, 7 fala sobre isso.")]
        )
        let provider = LocalLibraryResearchProvider {
            (items: [item], indexes: [item.id: index])
        }

        let results = try await provider.search(ResearchQuery(text: "oração"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].kind, .localDocument)
        XCTAssertEqual(results[0].libraryItemID, item.id)
        XCTAssertNotNil(results[0].locator)
        XCTAssertTrue(results[0].isAvailableOffline)
        XCTAssertTrue(results[0].title.contains("Oração"))

        let none = try await provider.search(ResearchQuery(text: "zzz-inexistente"))
        XCTAssertTrue(none.isEmpty)
    }

    func testProvedorDePesquisasSalvasEncontraPorNota() async throws {
        let saved = SavedResearch(
            query: "oração",
            result: ResearchResultPayload(
                providerID: ResearchProviderID.wolPublicSearch,
                title: "Oração",
                urlString: "https://wol.jw.org/pt/wol/d/r5/lp-t/1200003543",
                kind: .publication
            ),
            note: "Definição usada no esboço"
        )
        let provider = SavedResearchProvider { [saved] }
        let results = try await provider.search(ResearchQuery(text: "esboço"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Oração")
    }
}

final class ResearchServiceTests: XCTestCase {

    private let oraçaoHTMLFixture = "wol/resultados-pesquisa.html"

    private func makeService(
        fetcher: StubHTTPFetcher? = nil,
        repository: InMemoryResearchRepository? = nil,
        isOnline: @escaping @Sendable () async -> Bool = { true },
        items: [LibraryItem] = [],
        indexes: [UUID: LibraryTextIndex] = [:]
    ) -> ResearchService {
        ResearchService.standard(
            policy: ResearchAccessPolicy(minimumRequestInterval: 0.0001),
            repository: repository,
            fetcher: fetcher ?? StubHTTPFetcher(response: .success(HTTPFetchResponse(statusCode: 200, data: Data()))),
            libraryLoader: { (items: items, indexes: indexes) },
            savedLoader: { [] },
            isOnline: isOnline,
            sleeper: { _ in }
        )
    }

    func testCombinaProvedoresEOrdenaResultados() async throws {
        let html = try Fixtures.string(oraçaoHTMLFixture)
        let fetcher = StubHTTPFetcher(response: .success(HTTPFetchResponse(statusCode: 200, data: Data(html.utf8))))

        let item = LibraryItem(
            title: "Meu material",
            kind: .plainText,
            fileName: "m.txt",
            fileExtension: "txt",
            fileSize: 10,
            contentHash: "h",
            indexStatus: .indexed
        )
        let index = LibraryTextIndexBuilder.build(
            itemID: item.id,
            units: [(title: "Oração", text: "Oração sincera e constante.")]
        )

        let service = makeService(
            fetcher: fetcher,
            repository: nil,
            items: [item],
            indexes: [item.id: index]
        )
        let outcome = await service.search("oração")

        XCTAssertEqual(outcome.status, .success)
        XCTAssertFalse(outcome.results.isEmpty)
        XCTAssertEqual(outcome.results.first?.providerID, ResearchProviderID.localLibrary, "Conteúdo local vem primeiro")
        XCTAssertTrue(outcome.results.contains { $0.providerID == ResearchProviderID.wolPublicSearch })
        XCTAssertTrue(outcome.results.contains { $0.providerID == ResearchProviderID.jwOrgOfficialLink })
        XCTAssertTrue(outcome.providerErrors.isEmpty)
    }

    func testSemConexaoUsaOfflineEMantemLocais() async throws {
        let service = makeService(isOnline: { false })
        // Sem os links oficiais, nada pode ser devolvido offline.
        let outcome = await service.search(
            "oração",
            enabledProviderIDs: [ResearchProviderID.scripture, ResearchProviderID.localLibrary, ResearchProviderID.wolPublicSearch]
        )
        XCTAssertEqual(outcome.status, .offline)
        XCTAssertTrue(outcome.results.isEmpty)
        XCTAssertNotNil(outcome.providerErrors[ResearchProviderID.wolPublicSearch])
    }

    func testCacheEvitaSegundaConsultaERefreshForca() async throws {
        let html = try Fixtures.string(oraçaoHTMLFixture)
        let fetcher = StubHTTPFetcher(responses: [
            .success(HTTPFetchResponse(statusCode: 200, data: Data(html.utf8))),
            .success(HTTPFetchResponse(statusCode: 200, data: Data(html.utf8)))
        ])
        let repository = InMemoryResearchRepository()
        let service = makeService(fetcher: fetcher, repository: repository)

        _ = await service.search("oração")
        let firstCount = await fetcher.callCount()
        XCTAssertEqual(firstCount, 1)

        let cachedOutcome = await service.search("oração")
        XCTAssertTrue(cachedOutcome.cachedProviderIDs.contains(ResearchProviderID.wolPublicSearch))
        let secondCount = await fetcher.callCount()
        XCTAssertEqual(secondCount, 1, "A segunda consulta usa o cache")

        _ = await service.search("oração", forceRefresh: true)
        let thirdCount = await fetcher.callCount()
        XCTAssertEqual(thirdCount, 2, "forceRefresh ignora o cache")
    }

    func testFalhaDeRedeUsaCacheAntigo() async throws {
        let html = try Fixtures.string(oraçaoHTMLFixture)
        let repository = InMemoryResearchRepository()
        // Cache antigo (fora da validade) gravado manualmente.
        let payload = ResearchResultPayload(
            providerID: ResearchProviderID.wolPublicSearch,
            title: "Oração",
            publication: "Estudo Perspicaz",
            urlString: "https://wol.jw.org/pt/wol/d/r5/lp-t/1200003543",
            kind: .publication,
            accessedAt: Date(timeIntervalSince1970: 1_000)
        )
        try await repository.cache(
            CachedResearchResults(
                query: "oração",
                providerID: ResearchProviderID.wolPublicSearch,
                results: [payload],
                storedAt: Date(timeIntervalSince1970: 1_000)
            ),
            forKey: "\(ResearchProviderID.wolPublicSearch)|oracao"
        )

        let fetcher = StubHTTPFetcher(responses: [.failure(ResearchProviderError.offline)])
        let service = makeService(fetcher: fetcher, repository: repository)
        let outcome = await service.search("oração")

        XCTAssertTrue(outcome.results.contains { $0.title == "Oração" }, "Cache antigo é usado quando a rede falha")
        XCTAssertTrue(outcome.cachedProviderIDs.contains(ResearchProviderID.wolPublicSearch))
        XCTAssertNotNil(outcome.providerErrors[ResearchProviderID.wolPublicSearch])
    }

    func testRegistraHistoricoInclusiveDeFalhas() async throws {
        let repository = InMemoryResearchRepository()
        // Apenas provedores de rede: assim a consulta realmente falha.
        let service = makeService(
            fetcher: StubHTTPFetcher(responses: [.failure(ResearchProviderError.offline)]),
            repository: repository,
            isOnline: { true }
        )
        _ = await service.search(
            "oração",
            enabledProviderIDs: [ResearchProviderID.localLibrary, ResearchProviderID.wolPublicSearch]
        )
        let history = try await repository.searchHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.query, "oração")
        XCTAssertTrue(history.first?.failed ?? false)
        XCTAssertEqual(history.first?.resultCount, 0)
    }

    func testDeduplicaResultadosRepetidos() async {
        // Dois provedores idênticos devolvem os mesmos endereços; o serviço
        // deve apresentar cada endereço apenas uma vez.
        let service = ResearchService(
            providers: [
                OfficialLinkResearchProvider(),
                OfficialLinkResearchProvider()
            ]
        )
        let outcome = await service.search("João 3:16")
        XCTAssertFalse(outcome.results.isEmpty)
        let urls = outcome.results.compactMap { $0.url?.absoluteString }
        XCTAssertEqual(urls.count, outcome.results.count, "Todo resultado tem endereço")
        XCTAssertEqual(Set(urls).count, urls.count, "Nem URLs repetidas nem resultados duplicados")
    }

    func testSemProvedoresHabilitadosExplica() async {
        let service = makeService()
        let outcome = await service.search("oração", enabledProviderIDs: [])
        XCTAssertEqual(outcome.status, .failed("Nenhum provedor de pesquisa está habilitado nas configurações."))
    }

    func testConsultaVaziaNaoPesquisa() async {
        let service = makeService()
        let outcome = await service.search("   ")
        XCTAssertEqual(outcome.status, .empty)
        XCTAssertTrue(outcome.results.isEmpty)
    }
}
