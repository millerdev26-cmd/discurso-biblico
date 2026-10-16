//
//  SwiftDataRepositoriesTests.swift
//  DiscursoBiblicoTests
//
//  Testes dos armazenamentos do SwiftData (registros com colunas de índice +
//  o modelo completo do núcleo em JSON).
//
//  Este arquivo só é compilado onde o SwiftData existe (iOS 17+/macOS 14+).
//  No script de verificação em Linux ele é ignorado (ver
//  `Scripts/verify_app_logic.sh`).
//

#if canImport(SwiftData)
import DiscursoCore
import Foundation
import SwiftData
import XCTest
@testable import DiscursoBiblico

final class SwiftDataRepositoriesTests: XCTestCase {

    // MARK: Infraestrutura

    /// Contêiner em memória com o esquema completo do aplicativo.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SpeechRecord.self,
            SpeechFolderRecord.self,
            LibraryItemRecord.self,
            LibraryIndexRecord.self,
            SavedResearchRecord.self,
            SearchHistoryRecord.self,
            CachedResearchRecord.self,
            SettingsRecord.self,
            ReadingProfileRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: Discursos

    func testDiscursoSalvoCarregadoEExcluído() async throws {
        let container = try makeContainer()
        let repository = SwiftDataSpeechRepository(store: SpeechDataStore(modelContainer: container))

        var speech = AppSpeechFactory.makeSpeech()
        speech.title = "Título atualizado"
        try await repository.save(speech)

        let summaries = try await repository.loadSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.title, "Título atualizado")
        XCTAssertEqual(summaries.first?.wordCount, speech.wordCount)

        let loaded = try await repository.load(id: speech.id)
        XCTAssertEqual(loaded, speech, "O payload JSON deveria devolver o discurso idêntico")

        // Salvar de novo atualiza o registro, sem duplicar.
        var favorite = speech
        favorite.isFavorite = true
        try await repository.save(favorite)
        let all = try await repository.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].isFavorite)

        try await repository.delete(id: speech.id)
        let remaining = try await repository.loadSummaries()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCarregarDiscursoInexistenteLançaErro() async throws {
        let container = try makeContainer()
        let repository = SwiftDataSpeechRepository(store: SpeechDataStore(modelContainer: container))

        do {
            _ = try await repository.load(id: UUID())
            XCTFail("Esperava erro para discurso inexistente")
        } catch {
            // Esperado: a interface mostra a mensagem do erro.
        }
    }

    func testPastasSãoSubstituídasEmConjunto() async throws {
        let container = try makeContainer()
        let repository = SwiftDataSpeechRepository(store: SpeechDataStore(modelContainer: container))

        let first = SpeechFolder(name: "Primeira", sortIndex: 0)
        let second = SpeechFolder(name: "Segunda", sortIndex: 1)
        try await repository.saveFolders([first, second])

        let folders = try await repository.folders()
        XCTAssertEqual(folders.map(\.name), ["Primeira", "Segunda"])

        // Reordenar e excluir: a lista gravada é a fonte de verdade.
        var reordered = second
        reordered.sortIndex = 0
        try await repository.saveFolders([reordered])
        let after = try await repository.folders()
        XCTAssertEqual(after.map(\.name), ["Segunda"])
    }

    func testAvisosDoRepositórioSãoEntreguesUmaVez() async throws {
        let container = try makeContainer()
        let repository = SwiftDataSpeechRepository(store: SpeechDataStore(modelContainer: container))

        await repository.note("Arquivo recuperado.")
        let warnings = await repository.takeWarnings()
        XCTAssertEqual(warnings.map(\.message), ["Arquivo recuperado."])

        let second = await repository.takeWarnings()
        XCTAssertTrue(second.isEmpty, "Os avisos são consumidos na primeira leitura")
    }

    // MARK: Biblioteca

    func testBibliotecaGuardaArquivoÍndiceERemoção() async throws {
        let container = try makeContainer()
        let root = AppTestSupport.makeTemporaryDirectory()
        defer { AppTestSupport.remove(root) }

        let files = LibraryFileStore(rootDirectory: root)
        let repository = SwiftDataLibraryRepository(store: LibraryDataStore(modelContainer: container), files: files)

        let item = AppSpeechFactory.makeLibraryItem()
        try files.store(data: Data("conteúdo do material".utf8), itemID: item.id, fileExtension: item.fileExtension)
        try await repository.save(item)

        let fileURL = await repository.fileURL(for: item)
        XCTAssertNotNil(fileURL, "O arquivo gravado deveria ser encontrado")

        let index = LibraryTextIndex(
            itemID: item.id,
            chunks: [
                LibraryTextChunk(
                    locator: ReadingLocator(kind: .chapterOffset, chapterIndex: 0, characterOffset: 0),
                    title: "Capítulo",
                    text: "conteúdo do material",
                    normalizedText: "conteudo do material"
                )
            ],
            builtAt: AppSpeechFactory.referenceDate
        )
        try await repository.saveIndex(index, for: item.id)
        let loadedIndex = try await repository.loadIndex(for: item.id)
        XCTAssertEqual(loadedIndex, index)

        // Regravar o índice da mesma obra atualiza (não duplica).
        try await repository.saveIndex(index, for: item.id)
        let again = try await repository.loadIndex(for: item.id)
        XCTAssertEqual(again, index)

        // Excluir remove registro, índice e o arquivo em disco.
        try await repository.delete(id: item.id)
        let items = try await repository.loadItems()
        XCTAssertTrue(items.isEmpty)
        let indexAfterDelete = try await repository.loadIndex(for: item.id)
        XCTAssertNil(indexAfterDelete)
        let fileAfterDelete = await repository.fileURL(for: item)
        XCTAssertNil(fileAfterDelete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.fileURL(for: item).path))
    }

    // MARK: Configurações

    func testConfiguraçõesSãoGravadasERecarregadas() async throws {
        let container = try makeContainer()
        let repository = SwiftDataSettingsRepository(store: SettingsDataStore(modelContainer: container))

        let initial = try await repository.settings()
        XCTAssertEqual(initial.wordsPerMinute, AppSettings.default.wordsPerMinute)

        var settings = initial
        settings.wordsPerMinute = 111
        settings.recentTags = ["fé"]
        try await repository.save(settings)

        let reloaded = try await repository.settings()
        XCTAssertEqual(reloaded.wordsPerMinute, 111)
        XCTAssertEqual(reloaded.recentTags, ["fé"])
    }

    func testPerfisDeLeituraSãoSemeadosNaPrimeiraAbertura() async throws {
        let container = try makeContainer()
        let repository = SwiftDataSettingsRepository(store: SettingsDataStore(modelContainer: container))

        let seeded = try await repository.readingProfiles()
        XCTAssertEqual(seeded.count, ReadingProfile.builtInProfiles.count)
        XCTAssertTrue(seeded.allSatisfy(\.isBuiltIn))

        // A segunda leitura não duplica os perfis sugeridos.
        let second = try await repository.readingProfiles()
        XCTAssertEqual(second.count, seeded.count)

        let custom = ReadingProfile(name: "Meu perfil", preferences: PresentationPreferences())
        try await repository.save([custom])
        let after = try await repository.readingProfiles()
        XCTAssertEqual(after.map(\.name), ["Meu perfil"])
    }

    // MARK: Pesquisa

    func testPesquisaSalvaEHistórico() async throws {
        let container = try makeContainer()
        let repository = SwiftDataResearchRepository(store: ResearchDataStore(modelContainer: container))

        let saved = AppSpeechFactory.makeSavedResearch()
        try await repository.save(saved)
        let stored = try await repository.savedResearch()
        XCTAssertEqual(stored, [saved])

        try await repository.deleteSavedResearch(id: saved.id)
        let afterDelete = try await repository.savedResearch()
        XCTAssertTrue(afterDelete.isEmpty)

        try await repository.record(SearchHistoryEntry(query: "amor", searchedAt: AppSpeechFactory.referenceDate))
        let history = try await repository.searchHistory()
        XCTAssertEqual(history.map(\.query), ["amor"])

        try await repository.clearSearchHistory()
        let cleared = try await repository.searchHistory()
        XCTAssertTrue(cleared.isEmpty)
    }

    func testHistóricoDePesquisaMantémSomenteOs200MaisRecentes() async throws {
        let container = try makeContainer()
        let repository = SwiftDataResearchRepository(store: ResearchDataStore(modelContainer: container))

        for offset in 0..<205 {
            let entry = SearchHistoryEntry(
                query: "consulta \(offset)",
                searchedAt: AppSpeechFactory.referenceDate.addingTimeInterval(Double(offset))
            )
            try await repository.record(entry)
        }

        let history = try await repository.searchHistory()
        XCTAssertEqual(history.count, 200)
        XCTAssertEqual(history.first?.query, "consulta 204")
        XCTAssertEqual(history.last?.query, "consulta 5")
    }

    func testCacheDePesquisaPorChaveÚnica() async throws {
        let container = try makeContainer()
        let repository = SwiftDataResearchRepository(store: ResearchDataStore(modelContainer: container))

        let payload = ResearchResultPayload(providerID: "wol", title: "Resultado antigo")
        try await repository.cache(
            CachedResearchResults(query: "salmo 23", providerID: "wol", results: [payload], storedAt: AppSpeechFactory.referenceDate),
            forKey: "wol|salmo 23"
        )

        let cached = try await repository.cachedResults(forKey: "wol|salmo 23")
        XCTAssertEqual(cached?.results.first?.title, "Resultado antigo")
        XCTAssertTrue(cached?.isFresh(lifetime: 3600, now: AppSpeechFactory.referenceDate.addingTimeInterval(60)) ?? false)

        let updated = ResearchResultPayload(providerID: "wol", title: "Resultado novo")
        try await repository.cache(
            CachedResearchResults(query: "salmo 23", providerID: "wol", results: [updated], storedAt: AppSpeechFactory.referenceDate),
            forKey: "wol|salmo 23"
        )
        let afterUpdate = try await repository.cachedResults(forKey: "wol|salmo 23")
        XCTAssertEqual(afterUpdate?.results.first?.title, "Resultado novo")

        try await repository.clearCache()
        let cleared = try await repository.cachedResults(forKey: "wol|salmo 23")
        XCTAssertNil(cleared)
    }
}
#endif
