//
//  LibraryImportServiceTests.swift
//  DiscursoBiblicoTests
//
//  Testes da importação de materiais para a biblioteca pessoal
//  (`LibraryImportService`), do serviço de aplicativo que usa a triagem e a
//  indexação do núcleo.
//
//  Cobrem: importação válida (texto, Markdown, HTML, PDF), duplicidade,
//  formatos sem leitura, conteúdo protegido, arquivos digitais sem texto,
//  falhas de leitura e reindexação.
//

import DiscursoCore
import Foundation
import XCTest
@testable import DiscursoBiblico

/// Extrator de PDF controlado pelo teste (substitui o PDFKit).
private struct StubPDFExtractor: PDFTextExtracting {

    var extraction: PDFExtraction

    func extractText(from data: Data) -> PDFExtraction { extraction }
}

private let minimalPDFData = Data("%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n%%EOF".utf8)

final class LibraryImportServiceTests: XCTestCase {

    private var root: URL!
    private var files: LibraryFileStore!
    private var library: InMemoryLibraryRepository!
    private var service: LibraryImportService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = AppTestSupport.makeTemporaryDirectory()
        files = LibraryFileStore(rootDirectory: root.appendingPathComponent("files", isDirectory: true))
        try FileManager.default.createDirectory(at: files.rootDirectory, withIntermediateDirectories: true)
        // O repositório em memória aponta para a mesma pasta do
        // `LibraryFileStore`, como acontece no aplicativo (onde os dois são
        // unidos pelo `SwiftDataLibraryRepository`).
        library = InMemoryLibraryRepository(baseDirectory: files.rootDirectory)
        service = LibraryImportService(library: library, files: files)
    }

    override func tearDownWithError() throws {
        if let root { AppTestSupport.remove(root) }
        root = nil
        files = nil
        library = nil
        service = nil
        try super.tearDownWithError()
    }

    private func makeService(pdfExtraction: PDFExtraction) -> LibraryImportService {
        LibraryImportService(
            library: library,
            files: files,
            pdfTextExtracting: StubPDFExtractor(extraction: pdfExtraction)
        )
    }

    // MARK: Importação válida

    func testImportaTextoSimplesEIndexaOffline() async throws {
        let source = try AppTestSupport.writeFile(
            named: "esboço.txt",
            contents: "PRIMEIRA PARTE\nO amor de Deus é paciente.\n\nSEGUNDA PARTE\nDevemos permanecer fiéis.",
            in: root
        )

        let report = await service.importFiles(at: [source])

        XCTAssertTrue(report.failures.isEmpty, "Falhas inesperadas: \(report.failures.map(\.message))")
        XCTAssertEqual(report.imported.count, 1)
        XCTAssertTrue(report.duplicates.isEmpty)
        XCTAssertEqual(report.summaryMessage, "1 importado(s)")

        let item = try XCTUnwrap(report.imported.first)
        XCTAssertEqual(item.kind, .plainText)
        XCTAssertEqual(item.fileExtension, "txt")
        XCTAssertEqual(item.indexStatus, .indexed)
        XCTAssertEqual(item.unitCount, 2)
        XCTAssertGreaterThan(item.fileSize, 0)
        XCTAssertFalse(item.contentHash.isEmpty)
        XCTAssertTrue(files.fileExists(for: item), "O arquivo deveria ter sido copiado para o app")

        let stored = try await library.loadItems()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, item.id)

        let index = try await library.loadIndex(for: item.id)
        XCTAssertNotNil(index, "O índice deveria ter sido gravado")
        XCTAssertEqual(index?.chunks.count, 2)
        XCTAssertEqual(index?.chunks.first?.title, "PRIMEIRA PARTE")
        XCTAssertTrue(index?.fullText.contains("O amor de Deus é paciente.") ?? false)
    }

    func testImportaMarkdownConvertendoParaTexto() async throws {
        let source = try AppTestSupport.writeFile(
            named: "esboço.md",
            contents: "# Título do esboço\n\nTexto com **ênfase** e [uma ligação](https://example.com).",
            in: root
        )

        let report = await service.importFiles(at: [source])

        XCTAssertEqual(report.imported.count, 1)
        let item = try XCTUnwrap(report.imported.first)
        XCTAssertEqual(item.kind, .markdown)
        XCTAssertEqual(item.indexStatus, .indexed)

        let index = try await library.loadIndex(for: item.id)
        XCTAssertNotNil(index, "O índice deveria ter sido gravado")
        XCTAssertTrue(index?.fullText.contains("ênfase") ?? false, "A marcação deveria ser convertida em texto")
        XCTAssertFalse(index?.fullText.contains("**") ?? true)
    }

    func testImportaHTMLUsandoOTítulo() async throws {
        let source = try AppTestSupport.writeFile(
            named: "página.html",
            contents: "<html><head><title>Página de estudo</title></head><body><p>Conteúdo da página.</p></body></html>",
            in: root
        )

        let report = await service.importFiles(at: [source])

        XCTAssertEqual(report.imported.count, 1)
        let item = try XCTUnwrap(report.imported.first)
        XCTAssertEqual(item.kind, .html)
        XCTAssertEqual(item.indexStatus, .indexed)
        let index = try await library.loadIndex(for: item.id)
        XCTAssertNotNil(index, "O índice deveria ter sido gravado")
        XCTAssertTrue(index?.fullText.contains("Conteúdo da página") ?? false)
    }

    func testImportaPDFComTextoExtraídoPeloExtrator() async throws {
        let source = try AppTestSupport.writeFile(named: "documento.pdf", data: minimalPDFData, in: root)
        let service = makeService(pdfExtraction: PDFExtraction(
            pages: ["Primeira página com conteúdo.", "Segunda página também."],
            isEncrypted: false,
            warnings: []
        ))

        let report = await service.importFiles(at: [source])

        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(report.imported.count, 1)
        let item = try XCTUnwrap(report.imported.first)
        XCTAssertEqual(item.kind, .pdf)
        XCTAssertEqual(item.indexStatus, .indexed)
        XCTAssertEqual(item.unitCount, 2)

        let index = try await library.loadIndex(for: item.id)
        XCTAssertNotNil(index, "O índice deveria ter sido gravado")
        XCTAssertEqual(index?.chunks.map(\.title), ["Página 1", "Página 2"])
    }

    // MARK: Duplicidade

    func testDuplicadoÉRecusadoSemNovaCópia() async throws {
        let contents = "Conteúdo repetido para o teste de duplicidade."
        let first = try AppTestSupport.writeFile(named: "original.txt", contents: contents, in: root)
        let copy = try AppTestSupport.writeFile(named: "cópia.txt", contents: contents, in: root)

        let firstReport = await service.importFiles(at: [first])
        XCTAssertEqual(firstReport.imported.count, 1)

        let secondReport = await service.importFiles(at: [copy])
        XCTAssertTrue(secondReport.imported.isEmpty)
        XCTAssertEqual(secondReport.duplicates.count, 1)
        let duplicate = try XCTUnwrap(secondReport.duplicates.first)
        XCTAssertTrue(duplicate.message.contains("já está na biblioteca"))
        XCTAssertTrue(
            duplicate.recovery?.contains("original") ?? false,
            "A mensagem deveria apontar o material já existente; obteve: \(duplicate.recovery ?? "nil")"
        )

        let stored = try await library.loadItems()
        XCTAssertEqual(stored.count, 1, "O duplicado não deveria ser gravado")
    }

    // MARK: Rejeições com mensagem clara

    func testExtensãoDesconhecidaÉRejeitadaComMensagem() async throws {
        let source = try AppTestSupport.writeFile(named: "arquivo.xyz", contents: "conteúdo", in: root)

        let report = await service.importFiles(at: [source])

        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        let failure = try XCTUnwrap(report.failures.first)
        XCTAssertEqual(failure.fileName, "arquivo.xyz")
        XCTAssertTrue(failure.message.contains("não está em um formato reconhecido"))
    }

    func testArquivoVazioÉRejeitado() async throws {
        let source = try AppTestSupport.writeFile(named: "vazio.txt", contents: "", in: root)

        let report = await service.importFiles(at: [source])

        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(try XCTUnwrap(report.failures.first).message.contains("vazio"))
    }

    func testPDFComAssinaturaInválidaÉRejeitado() async throws {
        let source = try AppTestSupport.writeFile(named: "falso.pdf", contents: "isto não é um PDF", in: root)

        let report = await service.importFiles(at: [source])

        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(try XCTUnwrap(report.failures.first).message.contains("corrompido"))
    }

    func testArquivoIlegívelEntraComoFalha() async throws {
        let missing = root.appendingPathComponent("não-existe.txt")

        let report = await service.importFiles(at: [missing])

        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(try XCTUnwrap(report.failures.first).message.contains("Não foi possível ler o arquivo"))
    }

    // MARK: Formatos sem leitura e conteúdo protegido

    func testFormatoSemLeituraÉGuardadoComoReferência() async throws {
        let source = try AppTestSupport.writeFile(named: "manual.docx", contents: "documento sintético", in: root)

        let report = await service.importFiles(at: [source])

        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(report.imported.count, 1)
        let item = try XCTUnwrap(report.imported.first)
        XCTAssertEqual(item.kind, .unsupported)
        XCTAssertEqual(item.indexStatus, .failed)
        XCTAssertTrue(files.fileExists(for: item), "O arquivo continua guardado para uso externo")
        XCTAssertTrue(
            report.warnings.contains { $0.contains("ainda não pode ser lido") },
            "Deveria avisar que o formato não é lido no app; avisos: \(report.warnings)"
        )
    }

    func testPDFProtegidoÉRecusadoPorPadrão() async throws {
        let encrypted = Data("%PDF-1.4\n1 0 obj\n<< /Encrypt 2 0 R >>\nendobj\ntrailer\n%%EOF".utf8)
        let source = try AppTestSupport.writeFile(named: "protegido.pdf", data: encrypted, in: root)

        let report = await service.importFiles(at: [source])

        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        let failure = try XCTUnwrap(report.failures.first)
        XCTAssertTrue(failure.message.contains("protegido (DRM)"))
        XCTAssertTrue(failure.recovery?.contains("aplicativo oficial") ?? false)
    }

    func testPDFProtegidoPodeSerGuardadoComoReferênciaSemIndexar() async throws {
        let encrypted = Data("%PDF-1.4\n1 0 obj\n<< /Encrypt 2 0 R >>\nendobj\ntrailer\n%%EOF".utf8)
        let source = try AppTestSupport.writeFile(named: "protegido.pdf", data: encrypted, in: root)
        let service = makeService(pdfExtraction: PDFExtraction(pages: [], isEncrypted: true, warnings: []))

        let report = await service.importFiles(
            at: [source],
            policy: ImportPolicy(keepsProtectedContent: true)
        )

        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(report.imported.count, 1)
        let item = try XCTUnwrap(report.imported.first)
        XCTAssertTrue(item.isProtected)
        XCTAssertEqual(item.indexStatus, .failed)
        XCTAssertTrue(
            report.warnings.contains { $0.contains("não será indexado") },
            "Deveria explicar que o protegido não é indexado; avisos: \(report.warnings)"
        )
    }

    // MARK: PDFs sem texto (digitalizados)

    func testPDFDigitalizadoGeraAvisoEMaterialContinuaDisponível() async throws {
        let source = try AppTestSupport.writeFile(named: "digitalizado.pdf", data: minimalPDFData, in: root)
        let service = makeService(pdfExtraction: PDFExtraction(
            pages: ["", ""],
            isEncrypted: false,
            warnings: ["Nenhum texto pôde ser extraído: o PDF parece ser digitalizado (imagens)."]
        ))

        let report = await service.importFiles(at: [source])

        XCTAssertTrue(report.failures.isEmpty, "O arquivo é válido; a falta de texto é um aviso")
        XCTAssertEqual(report.imported.count, 1)
        let item = try XCTUnwrap(report.imported.first)
        XCTAssertEqual(item.indexStatus, .failed)
        XCTAssertEqual(item.indexFailureReason, "Nenhum texto pôde ser extraído do arquivo.")
        XCTAssertTrue(
            report.warnings.contains { $0.contains("Nenhum texto pôde ser extraído") },
            "Avisos: \(report.warnings)"
        )
        let stored = try await library.loadItems()
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(files.fileExists(for: item), "O PDF continua disponível para leitura no visualizador")
    }

    // MARK: Lote

    func testLoteContinuaNãoParaNPrimeiroErro() async throws {
        let validText = try AppTestSupport.writeFile(named: "um.txt", contents: "Texto do primeiro material.", in: root)
        let invalid = try AppTestSupport.writeFile(named: "dois.xyz", contents: "conteúdo", in: root)
        let validMarkdown = try AppTestSupport.writeFile(named: "três.md", contents: "# Segundo material\n\nConteúdo.", in: root)

        let report = await service.importFiles(at: [validText, invalid, validMarkdown])

        XCTAssertEqual(report.imported.count, 2)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.summaryMessage, "2 importado(s) · 1 com problema")
        let stored = try await library.loadItems()
        XCTAssertEqual(stored.count, 2)
    }

    func testMesmoArquivoNoLoteNãoÉImportadoDuasVezes() async throws {
        let source = try AppTestSupport.writeFile(named: "único.txt", contents: "Conteúdo importado uma vez só.", in: root)

        let report = await service.importFiles(at: [source, source])

        XCTAssertEqual(report.imported.count, 1)
        XCTAssertEqual(report.duplicates.count, 1)
    }

    // MARK: Reindexação

    func testReindexarSemArquivoFalhaComMensagemClara() async throws {
        let item = AppSpeechFactory.makeLibraryItem()
        try await library.save(item)

        let result = await service.reindex(item)

        guard case .failure(let error) = result else {
            return XCTFail("Esperava falha ao reindexar sem arquivo")
        }
        guard case .unreadableFile(let reason) = error else {
            return XCTFail("Esperava unreadableFile, obteve \(error)")
        }
        XCTAssertTrue(reason.contains("não está mais disponível"))
    }

    func testReindexarMaterialDisponívelAtualizaÍndiceESituação() async throws {
        var item = AppSpeechFactory.makeLibraryItem()
        item.indexStatus = .failed
        item.indexFailureReason = "Falha anterior."
        try files.store(data: Data("Agora o conteúdo é legível para indexação.".utf8), itemID: item.id, fileExtension: item.fileExtension)
        try await library.save(item)

        let result = await service.reindex(item)

        guard case .success(let updated) = result else {
            return XCTFail("A reindexação deveria funcionar; obteve \(result)")
        }
        XCTAssertEqual(updated.indexStatus, .indexed)
        XCTAssertNil(updated.indexFailureReason)

        let index = try await library.loadIndex(for: item.id)
        XCTAssertNotNil(index, "O índice deveria ter sido gravado")
        XCTAssertTrue(index?.fullText.contains("Agora o conteúdo é legível") ?? false)
    }
}
