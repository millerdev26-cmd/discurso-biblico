//
//  ImportServiceTests.swift
//  DiscursoCoreTests
//
//  Testes da triagem de importação e da indexação local.
//
//  As fixtures são sintéticas (geradas por `Scripts/make_fixtures.py`).
//

import XCTest
@testable import DiscursoCore

final class ImportServiceTests: XCTestCase {

    private func prepared(
        _ fixturePath: String,
        title: String? = nil,
        existing: [LibraryItem] = [],
        policy: ImportPolicy = .default,
        fileName: String? = nil
    ) throws -> PreparedImport {
        let data = try Fixtures.data(fixturePath)
        let name = fileName ?? (fixturePath as NSString).lastPathComponent
        return try ImportService.prepare(
            data: data,
            originalFileName: name,
            titleOverride: title,
            existingItems: existing,
            policy: policy
        )
    }

    // MARK: Classificação

    func testClassificaExtensoes() {
        XCTAssertEqual(ImportService.classify(fileName: "livro.epub"), .epub)
        XCTAssertEqual(ImportService.classify(fileName: "artigo.PDF"), .pdf)
        XCTAssertEqual(ImportService.classify(fileName: "notas.txt"), .plainText)
        XCTAssertEqual(ImportService.classify(fileName: "esboco.md"), .markdown)
        XCTAssertEqual(ImportService.classify(fileName: "pagina.html"), .html)
        XCTAssertEqual(ImportService.classify(fileName: "documento.docx"), .unsupported)
        XCTAssertEqual(ImportService.classify(fileName: "publicacao.jwpub"), .unsupported)
        XCTAssertNil(ImportService.classify(fileName: "arquivo.xyz"))
        XCTAssertNil(ImportService.classify(fileName: "semextensao"))
    }

    // MARK: Arquivos válidos

    func testImportaTextoEPreparaItem() throws {
        let result = try prepared("library/exemplo.txt")
        XCTAssertEqual(result.item.kind, .plainText)
        XCTAssertEqual(result.item.fileExtension, "txt")
        XCTAssertGreaterThan(result.item.fileSize, 0)
        XCTAssertFalse(result.item.contentHash.isEmpty)
        XCTAssertFalse(result.isDuplicate)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.item.title, "exemplo", "Título provisório vem do nome do arquivo")
    }

    func testTituloEscolhidoPeloUsuarioTemPrioridade() throws {
        let result = try prepared("library/exemplo.md", title: "Meu esboço")
        XCTAssertEqual(result.item.title, "Meu esboço")
    }

    func testImportaPDFValido() throws {
        let result = try prepared("library/documento.pdf")
        XCTAssertEqual(result.item.kind, .pdf)
        XCTAssertFalse(result.item.isProtected)
    }

    func testImportaEPUBValido() throws {
        let result = try prepared("epubs/epub3-nav.epub")
        XCTAssertEqual(result.item.kind, .epub)
        XCTAssertEqual(result.item.indexStatus, .pending)
        XCTAssertFalse(result.item.isProtected)
    }

    // MARK: Rejeições

    func testRejeitaExtensaoDesconhecida() throws {
        let data = try Fixtures.data("library/exemplo.txt")
        XCTAssertThrowsError(try ImportService.prepare(data: data, originalFileName: "arquivo.xyz")) { error in
            guard case ImportError.unsupportedExtension = error else {
                return XCTFail("Esperava unsupportedExtension, obteve \(error)")
            }
        }
    }

    func testRejeitaArquivoVazio() {
        XCTAssertThrowsError(try ImportService.prepare(data: Data(), originalFileName: "vazio.txt")) { error in
            XCTAssertEqual(error as? ImportError, .emptyFile)
        }
    }

    func testRejeitaArquivoGrandeDemais() throws {
        let data = try Fixtures.data("library/exemplo.txt")
        let policy = ImportPolicy(maximumFileSize: 10)
        XCTAssertThrowsError(try ImportService.prepare(data: data, originalFileName: "grande.txt", policy: policy)) { error in
            guard case ImportError.fileTooLarge = error else {
                return XCTFail("Esperava fileTooLarge, obteve \(error)")
            }
        }
    }

    func testRejeitaEPUBCorrompido() throws {
        let data = try Fixtures.data("epubs/corrompido.epub")
        XCTAssertThrowsError(try ImportService.prepare(data: data, originalFileName: "corrompido.epub")) { error in
            guard case ImportError.invalidContent = error else {
                return XCTFail("Esperava invalidContent, obteve \(error)")
            }
        }
    }

    func testRejeitaPDFComAssinaturaErrada() {
        let data = Data("não é pdf, mas tem extensão.pdf".utf8)
        XCTAssertThrowsError(try ImportService.prepare(data: data, originalFileName: "falso.pdf")) { error in
            guard case ImportError.invalidContent = error else {
                return XCTFail("Esperava invalidContent, obteve \(error)")
            }
        }
    }

    func testRejeitaTextoBinario() {
        let bytes = Data([0x00, 0x01, 0x02, 0x00, 0xFF, 0x00, 0x42, 0x00])
        XCTAssertThrowsError(try ImportService.prepare(data: bytes, originalFileName: "binario.txt")) { error in
            guard case ImportError.invalidContent = error else {
                return XCTFail("Esperava invalidContent, obteve \(error)")
            }
        }
    }

    // MARK: Proteção (DRM)

    func testRecusaEPUBProtegidoPorPadrao() throws {
        let data = try Fixtures.data("epubs/com-drn.epub")
        XCTAssertThrowsError(try ImportService.prepare(data: data, originalFileName: "protegido.epub")) { error in
            XCTAssertEqual(error as? ImportError, .protectedContent(format: "EPUB"))
        }
    }

    func testMantemEPUBProtegidoQuandoPermitido() throws {
        let data = try Fixtures.data("epubs/com-drn.epub")
        let policy = ImportPolicy(keepsProtectedContent: true)
        let result = try ImportService.prepare(data: data, originalFileName: "protegido.epub", policy: policy)
        XCTAssertTrue(result.item.isProtected)
        XCTAssertEqual(result.warnings, [.protectedContentKept("EPUB")])
    }

    func testRecusaPDFProtegido() throws {
        let data = try Fixtures.data("library/protegido.pdf")
        XCTAssertThrowsError(try ImportService.prepare(data: data, originalFileName: "protegido.pdf")) { error in
            XCTAssertEqual(error as? ImportError, .protectedContent(format: "PDF"))
        }
    }

    // MARK: Formatos sem suporte

    func testMantemDOCXComAviso() {
        let data = Data("PK conteúdo docx sintético".utf8)
        let result = try? ImportService.prepare(data: data, originalFileName: "documento.docx")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.item.kind, .unsupported)
        XCTAssertEqual(result?.item.indexStatus, .failed)
        XCTAssertEqual(result?.warnings.first, .formatWithoutReader("DOCX"))
    }

    func testRecusaDOCXQuandoConfiguradoAssim() {
        let data = Data("PK conteúdo docx sintético".utf8)
        let policy = ImportPolicy(storesUnsupportedFormats: false)
        XCTAssertThrowsError(try ImportService.prepare(data: data, originalFileName: "documento.docx", policy: policy)) { error in
            XCTAssertEqual(error as? ImportError, .formatNotSupported("DOCX"))
        }
    }

    // MARK: Duplicados

    func testDetectaDuplicadoPorHashETamanho() throws {
        let data = try Fixtures.data("library/exemplo.txt")
        let first = try ImportService.prepare(data: data, originalFileName: "exemplo.txt")
        let second = try ImportService.prepare(
            data: data,
            originalFileName: "copia.txt",
            existingItems: [first.item]
        )
        XCTAssertTrue(second.isDuplicate)
        XCTAssertEqual(second.duplicateOf, first.item.id)
    }

    func testMesmoTamanhoComConteudoDiferenteNaoEDuplicado() throws {
        let data = try Fixtures.data("library/exemplo.txt")
        let first = try ImportService.prepare(data: data, originalFileName: "exemplo.txt")
        var changed = data
        changed[0] = changed[0] &+ 1
        let second = try ImportService.prepare(
            data: changed,
            originalFileName: "diferente.txt",
            existingItems: [first.item]
        )
        XCTAssertFalse(second.isDuplicate)
    }

    func testHashEstavelEDiferentePorConteudo() {
        let a = ImportService.contentHash(of: Data("abc".utf8))
        let b = ImportService.contentHash(of: Data("abc".utf8))
        let c = ImportService.contentHash(of: Data("abd".utf8))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertTrue(a.hasPrefix("fnv1a64:"))
    }

    // MARK: Nome de arquivo e título

    func testNomeArmazenadoUsaIdentificadorEExtensao() throws {
        let result = try prepared("library/exemplo.txt")
        XCTAssertEqual(result.item.fileName, "\(result.item.id.uuidString).txt")
        XCTAssertEqual(result.item.originalFileName, "exemplo.txt")
    }

    func testSugestaoDeTituloLimpaNome() {
        XCTAssertEqual(ImportService.suggestedTitle(fromFileName: "meu_discurso-final.txt"), "meu discurso final")
        XCTAssertEqual(ImportService.suggestedTitle(fromFileName: ".txt"), ".txt")
    }
}

// MARK: - Indexação

final class LibraryIndexerTests: XCTestCase {

    private func index(_ fixturePath: String, kind: LibraryItemKind, fileExtension: String) throws -> LibraryIndexingResult {
        try LibraryIndexer.buildIndex(
            itemID: UUID(),
            kind: kind,
            fileExtension: fileExtension,
            data: try Fixtures.data(fixturePath)
        )
    }

    func testIndexaTextoComSecoes() throws {
        let result = try index("library/exemplo.txt", kind: .plainText, fileExtension: "txt")
        XCTAssertGreaterThan(result.index.totalWordCount, 30)
        XCTAssertGreaterThanOrEqual(result.index.chunks.count, 3, "Deve separar as seções numeradas")
        XCTAssertTrue(result.index.fullText.contains("Filipenses 4:6, 7"))
    }

    func testIndexaMarkdownRemovendoMarcacao() throws {
        let result = try index("library/exemplo.md", kind: .markdown, fileExtension: "md")
        let text = result.index.fullText
        XCTAssertTrue(text.contains("Material em Markdown"))
        XCTAssertFalse(text.contains("**"), "Ênfase deve ser removida do texto indexado")
        XCTAssertFalse(text.contains("## "), "Marcadores de título devem sair")
        XCTAssertTrue(text.contains("Salmo 83:18"))
    }

    func testIndexaHTMLComEntidades() throws {
        let html = """
        <html><head><title>Artigo de teste</title></head>
        <body><h1>Oração</h1><p>Texto com <b>ênfase</b> e &amp; entidade.</p>
        <script>alert('x')</script></body></html>
        """
        let result = try LibraryIndexer.buildIndex(
            itemID: UUID(),
            kind: .html,
            fileExtension: "html",
            data: Data(html.utf8)
        )
        XCTAssertEqual(result.suggestedTitle, "Artigo de teste")
        XCTAssertTrue(result.index.fullText.contains("ênfase"))
        XCTAssertTrue(result.index.fullText.contains("& entidade"))
        XCTAssertFalse(result.index.fullText.contains("alert"))
    }

    func testIndexaEPUBPorCapitulos() throws {
        let result = try index("epubs/epub3-nav.epub", kind: .epub, fileExtension: "epub")
        XCTAssertEqual(result.unitCount, 2)
        XCTAssertEqual(result.suggestedTitle, "Como preparar um discurso")
        XCTAssertEqual(result.author, "Equipe Discurso Bíblico")
        XCTAssertEqual(result.index.chunks.count, 2, "Um pedaço por capítulo (curtos)")
        XCTAssertTrue(result.index.fullText.contains("João 3:16"))
    }

    func testIndexaPDFMinimo() throws {
        let result = try index("library/documento.pdf", kind: .pdf, fileExtension: "pdf")
        XCTAssertEqual(result.unitCount, 1)
        XCTAssertEqual(result.index.fullText, "PDF de exemplo do projeto")
    }

    func testRecusaPDFProtegidoNaIndexacao() throws {
        let data = try Fixtures.data("library/protegido.pdf")
        XCTAssertThrowsError(try LibraryIndexer.buildIndex(
            itemID: UUID(),
            kind: .pdf,
            fileExtension: "pdf",
            data: data
        )) { error in
            guard case LibraryIndexingError.corrupted(let reason) = error else {
                return XCTFail("Esperava corrupted, obteve \(error)")
            }
            XCTAssertTrue(reason.contains("protegido"))
        }
    }

    func testRecusaFormatoSemSuporte() {
        XCTAssertThrowsError(try LibraryIndexer.buildIndex(
            itemID: UUID(),
            kind: .unsupported,
            fileExtension: "docx",
            data: Data([0x50, 0x4B, 0x03, 0x04])
        )) { error in
            XCTAssertEqual(error as? LibraryIndexingError, .unsupportedKind("DOCX"))
        }
    }

    func testRecusaEpubInvalidoComMensagem() throws {
        XCTAssertThrowsError(try LibraryIndexer.buildIndex(
            itemID: UUID(),
            kind: .epub,
            fileExtension: "epub",
            data: Data("não é zip".utf8)
        )) { error in
            guard case LibraryIndexingError.corrupted = error else {
                return XCTFail("Esperava corrupted, obteve \(error)")
            }
        }
    }

    func testTextoVazioNaoGeraIndice() {
        XCTAssertThrowsError(try LibraryIndexer.buildIndex(
            itemID: UUID(),
            kind: .plainText,
            fileExtension: "txt",
            data: Data("   \n\n  ".utf8)
        )) { error in
            XCTAssertEqual(error as? LibraryIndexingError, .noTextFound)
        }
    }
}

// MARK: - Extrator de PDF

final class PDFTextExtractorTests: XCTestCase {

    func testExtraiTextoDoPDFDeExemplo() throws {
        let data = try Fixtures.data("library/documento.pdf")
        let extraction = PDFTextExtractor.extract(data: data)
        XCTAssertFalse(extraction.isEncrypted)
        XCTAssertEqual(extraction.pages, ["PDF de exemplo do projeto"])
    }

    func testDetectaPDFProtegido() throws {
        let data = try Fixtures.data("library/protegido.pdf")
        XCTAssertTrue(PDFTextExtractor.isEncrypted(data: data))
    }

    func testFluxoFlateDecodeEInvertido() throws {
        // "BT /F1 18 Tf 72 720 Td (Linha comprimida) Tj ET" comprimido com zlib.
        let content = "BT /F1 18 Tf 72 720 Td (Linha comprimida) Tj ET"
        let compressed = try ZlibCompressorForTests.compress(Array(content.utf8))
        var pdf = Data("%PDF-1.4\n".utf8)
        pdf.append(Data("4 0 obj\n<< /Length \(compressed.count) /Filter /FlateDecode >>\nstream\n".utf8))
        pdf.append(Data(compressed))
        pdf.append(Data("\nendstream\nendobj\n".utf8))
        let extraction = PDFTextExtractor.extract(data: pdf)
        XCTAssertEqual(extraction.pages, ["Linha comprimida"])
    }
}

/// Compressor DEFLATE mínimo para os testes (blocos "armazenados").
enum ZlibCompressorForTests {
    static func compress(_ bytes: [UInt8]) throws -> [UInt8] {
        var output: [UInt8] = [0x78, 0x01] // cabeçalho zlib
        var remaining = bytes
        while !remaining.isEmpty {
            let chunk = Array(remaining.prefix(0xFFFF))
            remaining.removeFirst(chunk.count)
            let isLast = remaining.isEmpty
            output.append(isLast ? 0x01 : 0x00)
            let length = UInt16(chunk.count)
            output.append(UInt8(length & 0xFF))
            output.append(UInt8(length >> 8))
            let complement = ~length
            output.append(UInt8(complement & 0xFF))
            output.append(UInt8(complement >> 8))
            output.append(contentsOf: chunk)
        }
        // Adler-32 não é verificado pela leitura. Valor fixo para completar.
        output.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        return output
    }
}
