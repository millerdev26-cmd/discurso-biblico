//
//  ExportBackupTests.swift
//  DiscursoCoreTests
//
//  Testes de exportação (TXT/Markdown/HTML/PDF) e de backup (exportar,
//  validar, restaurar e mesclar).
//

import XCTest
@testable import DiscursoCore

/// Constrói um discurso de exemplo com todos os tipos de bloco.
enum SpeechFactory {

    static func makeSpeech(
        id: UUID = UUID(),
        title: String = "A oração que Deus ouve",
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Speech {
        var speech = Speech(
            id: id,
            title: title,
            subtitle: "Estudo para a reunião",
            occasion: "Reunião de meio de semana",
            tags: ["oração", "estudo"],
            createdAt: now,
            updatedAt: now,
            plannedMinutes: 30
        )

        var section = SpeechSection(
            title: "Introdução",
            subtitle: "Abertura",
            isCompleted: true
        )
        section.blocks = [
            SpeechBlock(kind: .paragraph, text: "Boa noite a todos. Hoje vamos considerar *Filipenses 4:6, 7*."),
            SpeechBlock(kind: .scripture, text: "Não estejais ansiosos por nada", reference: BibleReferenceParser.uniqueReferences(in: "Filipenses 4:6-7").first),
            SpeechBlock(kind: .bulletList, items: ["Primeiro ponto", "Segundo ponto"]),
            SpeechBlock(kind: .cue, cue: .pause, cueDetail: "2 segundos"),
            SpeechBlock(kind: .note, text: "Observar o tempo", isPresenterNote: true)
        ]

        var second = SpeechSection(title: "Desenvolvimento", subtitle: "")
        second.blocks = [
            SpeechBlock(kind: .paragraph, text: "Texto do desenvolvimento com João 3:16."),
            SpeechBlock(kind: .quote, text: "Citação curta para reflexão.")
        ]

        speech.sections = [section, second]
        speech.privateNotes = "Nota privada do pregador."
        speech.sources = [
            SourceLink(
                title: "A Sentinela — janeiro",
                url: URL(string: "https://wol.jw.org/pt/wol/d/r5/lp-t/2026001"),
                kind: .onlinePublication,
                publication: "A Sentinela"
            )
        ]
        return speech
    }
}

final class SpeechExporterTests: XCTestCase {

    func testExportaTextoTXTSimples() throws {
        let speech = SpeechFactory.makeSpeech()
        let payload = try SpeechExporter.payload(for: speech, format: .plainText)
        XCTAssertEqual(payload.suggestedFileName, "A oração que Deus ouve.txt")
        XCTAssertEqual(payload.mimeType, "text/plain")
        XCTAssertFalse(payload.needsPDFRendering)
        XCTAssertTrue(payload.content.contains("A ORAÇÃO QUE DEUS OUVE"))
        XCTAssertTrue(payload.content.contains("1. Introdução"))
        XCTAssertTrue(payload.content.contains("Nota: Observar o tempo"), "Notas do apresentador entram no texto por padrão")
    }

    func testExportaSemNotasDoApresentador() throws {
        let speech = SpeechFactory.makeSpeech()
        let options = SpeechExportOptions(includePresenterNotes: false, includeSources: true, includeMetadata: true)
        let payload = try SpeechExporter.payload(for: speech, format: .plainText, options: options)
        XCTAssertFalse(payload.content.contains("Observar o tempo"))
        XCTAssertFalse(payload.content.contains("Nota privada do pregador"))
    }

    func testExportaMarkdownComEstrutura() throws {
        let speech = SpeechFactory.makeSpeech()
        let payload = try SpeechExporter.payload(for: speech, format: .markdown)
        XCTAssertEqual(payload.suggestedFileName, "A oração que Deus ouve.md")
        XCTAssertTrue(payload.content.hasPrefix("# A oração que Deus ouve"))
        XCTAssertTrue(payload.content.contains("## 1. Introdução"))
        XCTAssertTrue(payload.content.contains("📖 Filipenses 4:6-7"))
        XCTAssertTrue(payload.content.contains("> **Nota:** Observar o tempo"))
    }

    func testExportaHTMLAutocontido() throws {
        let speech = SpeechFactory.makeSpeech()
        let payload = try SpeechExporter.payload(for: speech, format: .html)
        XCTAssertEqual(payload.mimeType, "text/html")
        XCTAssertTrue(payload.content.contains("<!DOCTYPE html>"))
        XCTAssertTrue(payload.content.contains("<h1>A oração que Deus ouve</h1>"))
        XCTAssertTrue(payload.content.contains("<style>"))
    }

    func testPedidoDePDFUsaHTML() throws {
        let speech = SpeechFactory.makeSpeech()
        let request = try SpeechExporter.pdfRequest(for: speech)
        XCTAssertEqual(request.suggestedFileName, "A oração que Deus ouve.pdf")
        XCTAssertTrue(request.html.contains("<!DOCTYPE html>"))
        XCTAssertEqual(request.title, "A oração que Deus ouve")
    }

    func testNomesDeArquivoSaoSanitizados() throws {
        let speech = SpeechFactory.makeSpeech(title: "Fé/Amor: o \"caminho\" <melhor>")
        let payload = try SpeechExporter.payload(for: speech, format: .plainText)
        XCTAssertFalse(payload.suggestedFileName.contains("/"))
        XCTAssertFalse(payload.suggestedFileName.contains(":"))
        XCTAssertFalse(payload.suggestedFileName.contains("\""))
        XCTAssertTrue(payload.suggestedFileName.hasSuffix(".txt"))
    }

    func testDiscursoVazioNaoExporta() {
        let speech = Speech(id: UUID(), title: "Vazio")
        XCTAssertThrowsError(try SpeechExporter.payload(for: speech, format: .plainText)) { error in
            XCTAssertEqual(error as? SpeechExportError, .emptySpeech)
        }
    }

    func testSemMetadadosRemoveOcasiaoEDuracaoPlanejada() throws {
        let speech = SpeechFactory.makeSpeech()
        let options = SpeechExportOptions(includePresenterNotes: true, includeSources: false, includeMetadata: false)
        let payload = try SpeechExporter.payload(for: speech, format: .markdown, options: options)
        XCTAssertFalse(payload.content.contains("Reunião de meio de semana"))
        XCTAssertFalse(payload.content.contains("Duração planejada"))
        XCTAssertFalse(payload.content.contains("`oração`"))
    }
}

final class BackupServiceTests: XCTestCase {

    private func sampleData() -> (speeches: [Speech], folders: [SpeechFolder], items: [LibraryItem], research: [SavedResearch], settings: AppSettings, profiles: [ReadingProfile]) {
        let speech = SpeechFactory.makeSpeech()
        let folder = SpeechFolder(name: "Discursos públicos")
        let item = LibraryItem(
            title: "Revista de exemplo",
            kind: .epub,
            fileName: "abc.epub",
            fileExtension: "epub",
            fileSize: 1234,
            contentHash: "fnv1a64:0000000000000001",
            indexStatus: .indexed
        )
        let saved = SavedResearch(
            query: "oração",
            result: ResearchResultPayload(
                providerID: ResearchProviderID.wolPublicSearch,
                title: "Oração",
                urlString: "https://wol.jw.org/pt/wol/d/r5/lp-t/1200003543",
                kind: .publication
            ),
            note: "Boa definição"
        )
        return ([speech], [folder], [item], [saved], AppSettings.default, ReadingProfile.builtInProfiles)
    }

    func testExportaEImportaBackupCompleto() throws {
        let sample = sampleData()
        let data = try BackupService.export(
            speeches: sample.speeches,
            folders: sample.folders,
            libraryItems: sample.items,
            savedResearch: sample.research,
            settings: sample.settings,
            readingProfiles: sample.profiles
        )
        let restored = try BackupService.restore(data: data)
        XCTAssertEqual(restored.speeches.count, 1)
        XCTAssertEqual(restored.speeches.first?.id, sample.speeches.first?.id)
        XCTAssertEqual(restored.speeches.first?.displayTitle, "A oração que Deus ouve")
        XCTAssertEqual(restored.folders.first?.name, "Discursos públicos")
        XCTAssertEqual(restored.libraryItems.first?.title, "Revista de exemplo")
        XCTAssertEqual(restored.savedResearch.first?.note, "Boa definição")
        XCTAssertNotNil(restored.settings)
        XCTAssertEqual(restored.readingProfiles.count, sample.profiles.count)
        XCTAssertTrue(restored.warnings.isEmpty)
    }

    func testRecusaArquivoQueNaoEBackup() {
        let data = Data(#"{"format":"outro.app","formatVersion":1}"#.utf8)
        XCTAssertThrowsError(try BackupService.restore(data: data)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupService.restore(data: Data("nada de json".utf8))) { error in
            guard case BackupError.unreadable = error else {
                return XCTFail("Esperava unreadable, obteve \(error)")
            }
        }
    }

    func testRecusaBackupDeVersaoMaisNova() throws {
        let data = try BackupService.export(speeches: [SpeechFactory.makeSpeech()])
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["formatVersion"] = BackupEnvelope.currentFormatVersion + 1
        let modified = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try BackupService.restore(data: modified)) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion(BackupEnvelope.currentFormatVersion + 1))
        }
    }

    func testRecusaBackupVazio() throws {
        let data = try BackupService.export(speeches: [])
        XCTAssertThrowsError(try BackupService.restore(data: data)) { error in
            XCTAssertEqual(error as? BackupError, .emptyBackup)
        }
    }

    func testAvisaRegistroDeEsquemaMaisNovo() throws {
        var speech = SpeechFactory.makeSpeech()
        speech.schemaVersion = Speech.currentSchemaVersion + 1
        let data = try BackupService.export(speeches: [speech])
        let restored = try BackupService.restore(data: data)
        XCTAssertEqual(restored.speeches.count, 1)
        XCTAssertEqual(restored.warnings.count, 1)
        XCTAssertTrue(restored.warnings[0].contains("versão mais nova"))
    }

    func testInspecionarNaoLanca() {
        let result = BackupService.inspect(data: Data(#"{"format":"x"}"#.utf8))
        switch result {
        case .success: XCTFail("Não deveria validar")
        case .failure(let error): XCTAssertEqual(error, .notABackup)
        }
    }

    func testMesclagemMantemMaisRecenteEAcrescentaNovos() throws {
        let sharedID = UUID()
        var older = SpeechFactory.makeSpeech(id: sharedID, title: "Antigo")
        older.updatedAt = Date(timeIntervalSince1970: 100)
        var newer = SpeechFactory.makeSpeech(id: sharedID, title: "Atualizado")
        newer.updatedAt = Date(timeIntervalSince1970: 200)
        let extra = SpeechFactory.makeSpeech(title: "Só do backup")

        let backupData = try BackupService.export(speeches: [newer, extra])
        let backup = try BackupService.restore(data: backupData)

        let merged = BackupService.merge(
            backup: backup,
            strategy: .merge,
            currentSpeeches: [older]
        )
        XCTAssertEqual(merged.speeches.count, 2)
        XCTAssertEqual(merged.speeches.first { $0.id == sharedID }?.title, "Atualizado")
        XCTAssertTrue(merged.speeches.contains { $0.title == "Só do backup" })
    }

    func testMesclagemComSubstituicaoDescartaAtuais() throws {
        let backupData = try BackupService.export(speeches: [SpeechFactory.makeSpeech(title: "Do backup")])
        let backup = try BackupService.restore(data: backupData)
        let merged = BackupService.merge(
            backup: backup,
            strategy: .replace,
            currentSpeeches: [SpeechFactory.makeSpeech(title: "Atual")]
        )
        XCTAssertEqual(merged.speeches.count, 1)
        XCTAssertEqual(merged.speeches.first?.title, "Do backup")
    }

    func testNomeDeArquivoDeBackup() {
        let name = BackupService.suggestedFileName(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(name.hasPrefix("discurso-biblico-"))
        XCTAssertTrue(name.hasSuffix(".json"))
    }

    func testResumoDescreveConteudo() throws {
        let sample = sampleData()
        let envelope = BackupService.makeEnvelope(
            speeches: sample.speeches,
            folders: sample.folders,
            libraryItems: sample.items,
            savedResearch: sample.research
        )
        let summary = envelope.summaryDescription
        XCTAssertTrue(summary.contains("1 discurso"))
        XCTAssertTrue(summary.contains("1 material"))
        XCTAssertTrue(summary.contains("1 pesquisa"))
    }
}
