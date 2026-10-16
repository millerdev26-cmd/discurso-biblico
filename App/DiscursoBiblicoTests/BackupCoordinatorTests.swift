//
//  BackupCoordinatorTests.swift
//  DiscursoBiblicoTests
//
//  Testes da exportação/restauração de backup pela camada do aplicativo:
//  montar o arquivo para compartilhar, inspecionar sem alterar nada e aplicar
//  o conteúdo (mesclar ou substituir).
//

import DiscursoCore
import Foundation
import XCTest
@testable import DiscursoBiblico

final class BackupCoordinatorTests: XCTestCase {

    private struct World {
        var coordinator: BackupCoordinator
        var speech: InMemorySpeechRepository
        var library: InMemoryLibraryRepository
        var research: InMemoryResearchRepository
        var settings: InMemorySettingsRepository
    }

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = AppTestSupport.makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        if let root { AppTestSupport.remove(root) }
        root = nil
        try super.tearDownWithError()
    }

    private func makeWorld() -> World {
        let speech = InMemorySpeechRepository()
        let library = InMemoryLibraryRepository()
        let research = InMemoryResearchRepository()
        let settings = InMemorySettingsRepository()
        let coordinator = BackupCoordinator(
            speech: speech,
            library: library,
            research: research,
            settings: settings
        )
        return World(coordinator: coordinator, speech: speech, library: library, research: research, settings: settings)
    }

    @discardableResult
    private func writeBackup(
        speeches: [Speech] = [],
        folders: [SpeechFolder] = [],
        libraryItems: [LibraryItem] = [],
        savedResearch: [SavedResearch] = [],
        settings: AppSettings? = nil,
        readingProfiles: [ReadingProfile] = [],
        named name: String = "backup.json"
    ) throws -> URL {
        let data = try BackupService.export(
            speeches: speeches,
            folders: folders,
            libraryItems: libraryItems,
            savedResearch: savedResearch,
            settings: settings,
            readingProfiles: readingProfiles,
            now: AppSpeechFactory.referenceDate
        )
        return try AppTestSupport.writeFile(named: name, data: data, in: root)
    }

    // MARK: Exportação

    func testExportaArquivoDeBackupComConteúdo() async throws {
        let world = makeWorld()
        try await world.speech.save(AppSpeechFactory.makeSpeech())
        try await world.library.save(AppSpeechFactory.makeLibraryItem())
        try await world.research.save(AppSpeechFactory.makeSavedResearch())

        let result = try await world.coordinator.exportToTemporaryFile(appVersion: "1.0")
        defer { try? FileManager.default.removeItem(at: result.fileURL) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        XCTAssertEqual(result.itemCount, 3)
        XCTAssertEqual(result.summary, "1 discurso(s), 1 material(is) da biblioteca e 1 fonte(s) salva(s).")

        let data = try Data(contentsOf: result.fileURL)
        guard case .success(let contents) = BackupService.inspect(data: data) else {
            return XCTFail("O arquivo exportado deveria ser um backup válido")
        }
        XCTAssertEqual(contents.speeches.count, 1)
        XCTAssertEqual(contents.libraryItems.count, 1)
        XCTAssertEqual(contents.savedResearch.count, 1)
        XCTAssertEqual(contents.readingProfiles.count, ReadingProfile.builtInProfiles.count)
    }

    // MARK: Inspeção

    func testInspecionarArquivoDeOutroAppÉRecusado() throws {
        let world = makeWorld()
        let url = try AppTestSupport.writeFile(named: "estranho.json", contents: "{\"hello\": \"world\"}", in: root)

        XCTAssertThrowsError(try world.coordinator.inspect(fileAt: url)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
    }

    func testInspecionarArquivoIlegívelÉRecusadoSemQuebrar() throws {
        let world = makeWorld()
        let url = try AppTestSupport.writeFile(named: "texto.txt", contents: "isto não é um backup", in: root)

        XCTAssertThrowsError(try world.coordinator.inspect(fileAt: url)) { error in
            guard case .unreadable = (error as? BackupError) else {
                return XCTFail("Esperava unreadable, obteve \(error)")
            }
        }
    }

    func testInspecionarBackupCompatívelNãoAlteraNada() async throws {
        let world = makeWorld()
        try await world.speech.save(AppSpeechFactory.makeSpeech(title: "Discurso atual"))
        let url = try writeBackup(speeches: [AppSpeechFactory.makeSpeech(title: "Discurso do backup")])

        let contents = try world.coordinator.inspect(fileAt: url)

        XCTAssertEqual(contents.speeches.map(\.title), ["Discurso do backup"])
        let current = try await world.speech.loadAll()
        XCTAssertEqual(current.map(\.title), ["Discurso atual"], "Inspecionar não pode alterar os dados")
    }

    // MARK: Restauração

    func testRestaurarEmModoMesclarMantémOsDadosAtuais() async throws {
        let world = makeWorld()
        try await world.speech.save(AppSpeechFactory.makeSpeech(title: "Discurso atual"))
        let backupSpeech = AppSpeechFactory.makeSpeech(title: "Discurso do backup")
        let backupItem = AppSpeechFactory.makeLibraryItem(title: "Material do backup")
        let url = try writeBackup(speeches: [backupSpeech], libraryItems: [backupItem])

        let result = try await world.coordinator.restore(fileAt: url, strategy: .merge)

        XCTAssertEqual(result.importedSpeeches, 2, "O modo mesclar soma o que já existia")
        XCTAssertEqual(result.importedLibraryItems, 1)
        XCTAssertTrue(result.warnings.isEmpty, "Avisos inesperados: \(result.warnings)")

        let speeches = try await world.speech.loadAll()
        XCTAssertEqual(Set(speeches.map(\.title)), ["Discurso atual", "Discurso do backup"])
        let items = try await world.library.loadItems()
        XCTAssertEqual(items.map(\.title), ["Material do backup"])
    }

    func testRestaurarEmModoSubstituirUsaOsDadosDoBackupEAvisa() async throws {
        let world = makeWorld()
        let current = AppSpeechFactory.makeSpeech(title: "Versão antiga")
        try await world.speech.save(current)

        var backupSpeech = AppSpeechFactory.makeSpeech(title: "Versão nova")
        backupSpeech.createdAt = AppSpeechFactory.referenceDate.addingTimeInterval(60)
        backupSpeech.updatedAt = backupSpeech.createdAt
        let url = try writeBackup(speeches: [backupSpeech])

        let result = try await world.coordinator.restore(fileAt: url, strategy: .replace)

        XCTAssertEqual(result.importedSpeeches, 1)
        XCTAssertTrue(
            result.warnings.contains { $0.contains("substituir") },
            "O modo substituir deveria explicar como os dados são combinados; avisos: \(result.warnings)"
        )

        let loaded = try await world.speech.load(id: backupSpeech.id)
        XCTAssertEqual(loaded.title, "Versão nova")
    }

    func testBackupIdaEVoltaPreservaODiscurso() async throws {
        let origin = makeWorld()
        let speech = AppSpeechFactory.makeSpeech()
        try await origin.speech.save(speech)
        let stored = try await origin.speech.load(id: speech.id)

        let export = try await origin.coordinator.exportToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: export.fileURL) }

        let destination = makeWorld()
        _ = try await destination.coordinator.restore(fileAt: export.fileURL, strategy: .merge)

        let restored = try await destination.speech.load(id: speech.id)
        XCTAssertEqual(restored, stored, "O discurso restaurado deveria ser idêntico ao gravado")
    }

    func testRestaurarConfiguraçõesEPerfis() async throws {
        var customSettings = AppSettings.default
        customSettings.wordsPerMinute = 111
        let profile = ReadingProfile(
            name: "Meu perfil",
            preferences: customSettings.defaultPresentation,
            createdAt: AppSpeechFactory.referenceDate
        )
        let url = try writeBackup(
            speeches: [AppSpeechFactory.makeSpeech()],
            settings: customSettings,
            readingProfiles: [profile]
        )

        let world = makeWorld()
        _ = try await world.coordinator.restore(fileAt: url, strategy: .merge)

        let settings = try await world.settings.settings()
        XCTAssertEqual(settings.wordsPerMinute, 111)
        let profiles = try await world.settings.readingProfiles()
        XCTAssertEqual(profiles.map(\.name), ["Meu perfil"])
    }

    func testRestaurarArquivoInválidoNãoAlteraOsDados() async throws {
        let world = makeWorld()
        try await world.speech.save(AppSpeechFactory.makeSpeech(title: "Intocado"))
        let url = try AppTestSupport.writeFile(named: "inválido.json", contents: "{\"foo\": 1}", in: root)

        do {
            _ = try await world.coordinator.restore(fileAt: url, strategy: .merge)
            XCTFail("Esperava falha ao restaurar um arquivo que não é backup")
        } catch {
            // Esperado: o erro chega à interface com a mensagem do BackupError.
        }

        let speeches = try await world.speech.loadAll()
        XCTAssertEqual(speeches.map(\.title), ["Intocado"])
    }
}
