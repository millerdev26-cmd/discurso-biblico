//
//  EPUBTests.swift
//  DiscursoCoreTests
//
//  Testes do leitor ZIP/DEFLATE e do analisador de EPUB.
//
//  As fixtures são geradas por `Scripts/make_fixtures.py` e contêm apenas
//  conteúdo sintético criado pelo próprio projeto.
//

import XCTest
@testable import DiscursoCore

/// Acesso às fixtures empacotadas no bundle de teste.
enum Fixtures {

    static func url(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: relativePath.replacingOccurrences(of: ".", with: "@@@"),
            withExtension: nil
        ) else {
            // Bundle.module mantém a estrutura de pastas; o caminho relativo
            // é resolvido a partir da raiz das fixtures.
            if let root = Bundle.module.resourceURL {
                let direct = root.appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: direct.path) {
                    return direct
                }
                let nested = root.appendingPathComponent("Fixtures/\(relativePath)")
                if FileManager.default.fileExists(atPath: nested.path) {
                    return nested
                }
            }
            XCTFail("Fixture não encontrada: \(relativePath)", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    static func data(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        try Data(contentsOf: try url(relativePath, file: file, line: line))
    }

    static func string(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        try String(contentsOf: try url(relativePath, file: file, line: line), encoding: .utf8)
    }
}

final class InflateTests: XCTestCase {

    private struct Case: Decodable {
        var name: String
        var compressed: String
        var expected: String
        var expectedSize: Int
    }

    private func loadCases() throws -> [Case] {
        let data = try Fixtures.data("inflate/cases.json")
        return try JSONDecoder().decode([Case].self, from: data)
    }

    func testFluxosGeradosPeloZlib() throws {
        let cases = try loadCases()
        XCTAssertGreaterThanOrEqual(cases.count, 8, "As fixtures de DEFLATE devem cobrir todos os modos")
        for testCase in cases {
            guard let compressed = Data(base64Encoded: testCase.compressed),
                  let expected = Data(base64Encoded: testCase.expected)
            else {
                return XCTFail("Base64 inválido em \(testCase.name)")
            }
            let decompressed = try Inflate.decompress(compressed, initialCapacity: testCase.expectedSize)
            XCTAssertEqual(
                decompressed,
                expected,
                "Falha ao descompactar o caso '\(testCase.name)' (\(testCase.expectedSize) bytes)"
            )
        }
    }

    func testModoArmazenado() throws {
        // Bloco armazenado (nível 0): "A" * 100
        let payload = String(repeating: "A", count: 100).data(using: .utf8)!
        let compressor = try XCTUnwrap(RawDeflateStoreBlock(payload: payload))
        let decompressed = try Inflate.decompress(compressor.encoded)
        XCTAssertEqual(decompressed, payload)
    }

    func testEntradaTruncada() throws {
        let cases = try loadCases()
        guard let first = cases.first(where: { $0.expectedSize > 100 }),
              let compressed = Data(base64Encoded: first.compressed) else {
            return XCTFail("Fixture ausente")
        }
        let truncated = compressed.prefix(compressed.count / 2)
        XCTAssertThrowsError(try Inflate.decompress(Data(truncated))) { error in
            XCTAssertTrue(error is CompressionError, "Esperava CompressionError, obteve \(error)")
        }
    }

    func testBlocoInvalido() {
        // BTYPE = 3 (reservado) => bloco inválido. Bits: BFINAL=1, BTYPE=11.
        let bytes = Data([0b0000_0111])
        XCTAssertThrowsError(try Inflate.decompress(bytes)) { error in
            XCTAssertEqual(error as? CompressionError, .invalidBlockType)
        }
    }

    func testCRC32Conhecido() {
        XCTAssertEqual(CRC32.checksum("123456789".data(using: .utf8)!), 0xCBF43926)
        XCTAssertEqual(CRC32.checksum(Data()), 0x00000000)
    }
}

/// Construtor mínimo de bloco DEFLATE "armazenado", usado para testar esse caminho.
struct RawDeflateStoreBlock {
    let encoded: Data

    init?(payload: Data) {
        guard payload.count <= 0xFFFF else { return nil }
        var data = Data()
        data.append(0x01) // BFINAL=1, BTYPE=00
        let length = UInt16(payload.count)
        data.append(contentsOf: [UInt8(length & 0xFF), UInt8(length >> 8)])
        let complement = ~length
        data.append(contentsOf: [UInt8(complement & 0xFF), UInt8(complement >> 8)])
        data.append(payload)
        self.encoded = data
    }
}

final class ZipArchiveTests: XCTestCase {

    func testListaEntradasDoEpub3() throws {
        let archive = try ZipArchive(data: try Fixtures.data("epubs/epub3-nav.epub"))
        XCTAssertTrue(archive.contains("mimetype"))
        XCTAssertTrue(archive.contains("META-INF/container.xml"))
        XCTAssertTrue(archive.contains("OEBPS/content.opf"))
        XCTAssertTrue(archive.contains("OEBPS/nav.xhtml"))
        XCTAssertFalse(archive.entries.isEmpty)
        XCTAssertTrue(archive.warnings.isEmpty, "Não esperava avisos: \(archive.warnings)")
    }

    func testExtraiMimetypeSemCompressao() throws {
        let archive = try ZipArchive(data: try Fixtures.data("epubs/epub3-nav.epub"))
        let mimetype = try XCTUnwrap(archive.string(forName: "mimetype"))
        XCTAssertEqual(mimetype, "application/epub+zip")
    }

    func testExtraiConteudoComprimidoEValidaCRC() throws {
        let archive = try ZipArchive(data: try Fixtures.data("epubs/epub3-nav.epub"))
        let chapter = try XCTUnwrap(archive.string(forName: "OEBPS/capitulo1.xhtml"))
        XCTAssertTrue(chapter.contains("Como preparar um discurso"))
        // A validação de CRC já ocorre dentro de `string(forName:)`.
    }

    func testDetectaCorrupcaoNoCRC() throws {
        var bytes = try Fixtures.data("epubs/epub3-nav.epub").map { $0 }
        let archive = try ZipArchive(data: Data(bytes))
        let entry = try XCTUnwrap(archive.entry(named: "OEBPS/capitulo1.xhtml"))

        // Corrompe um byte dentro dos dados comprimidos da entrada.
        let reader = ByteReaderForTests(data: Data(bytes))
        let dataOffset = try XCTUnwrap(reader.compressedDataOffset(of: entry))
        bytes[dataOffset + 4] = bytes[dataOffset + 4] ^ 0xFF
        let corrupted = try ZipArchive(data: Data(bytes))
        XCTAssertThrowsError(try corrupted.data(for: try XCTUnwrap(corrupted.entry(named: "OEBPS/capitulo1.xhtml"))))
    }

    func testArquivoInvalido() {
        XCTAssertThrowsError(try ZipArchive(data: Data("não é um zip".utf8)))
    }

    func testEntradasArmazenadasDoEpub2() throws {
        let archive = try ZipArchive(data: try Fixtures.data("epubs/epub2-ncx.epub"))
        let chapter = try XCTUnwrap(archive.string(forName: "OEBPS/capitulo1.xhtml"))
        XCTAssertTrue(chapter.contains("Escolha das referências"))
    }
}

/// Utilitário de teste para localizar os dados comprimidos de uma entrada.
private struct ByteReaderForTests {
    let data: Data

    func compressedDataOffset(of entry: ZipEntry) -> Int? {
        let base = data.startIndex + entry.localHeaderOffset
        guard base + 30 <= data.endIndex else { return nil }
        func uint16(_ offset: Int) -> Int {
            let index = base + offset
            return Int(data[index]) | (Int(data[index + 1]) << 8)
        }
        let nameLength = uint16(26)
        let extraLength = uint16(28)
        return entry.localHeaderOffset + 30 + nameLength + extraLength
    }
}

final class EPUBParserTests: XCTestCase {

    func testLeEpub3ComNavegacao() throws {
        let book = try EPUBParser.parse(data: try Fixtures.data("epubs/epub3-nav.epub"))
        XCTAssertEqual(book.metadata.title, "Como preparar um discurso")
        XCTAssertEqual(book.metadata.creators, ["Equipe Discurso Bíblico"])
        XCTAssertEqual(book.metadata.language, "pt-BR")
        XCTAssertEqual(book.metadata.packageVersion, "3.0")
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].title, "Como preparar um discurso")
        XCTAssertGreaterThan(book.wordCount, 40)
        XCTAssertNotNil(book.coverImagePath)
        XCTAssertTrue(book.diagnostics.hasNavigationDocument)
    }

    func testSumarioDoEpub3TemNiveis() throws {
        let book = try EPUBParser.parse(data: try Fixtures.data("epubs/epub3-nav.epub"))
        XCTAssertGreaterThanOrEqual(book.navigation.count, 4)
        XCTAssertEqual(book.navigation[0].title, "Como preparar um discurso")
        XCTAssertEqual(book.navigation[0].level, 0)
        XCTAssertEqual(book.navigation[0].chapterIndex, 0)
        let nested = try XCTUnwrap(book.navigation.first { $0.title == "Escolha das referências" })
        XCTAssertEqual(nested.level, 1)
        XCTAssertEqual(nested.fragment, "referencias")
    }

    func testLeEpub2ComNCX() throws {
        let book = try EPUBParser.parse(data: try Fixtures.data("epubs/epub2-ncx.epub"))
        XCTAssertEqual(book.metadata.title, "Manual de estudo (EPUB 2)")
        XCTAssertEqual(book.metadata.packageVersion, "2.0")
        XCTAssertTrue(book.diagnostics.usedNCXFallback)
        XCTAssertEqual(book.chapters.count, 2, "Itens com linear=\"no\" ficam fora da ordem de leitura")
        XCTAssertEqual(book.navigation.first?.title, "Introdução")
        XCTAssertEqual(book.navigation.count, 3)
        XCTAssertEqual(book.navigation[1].level, 1)
    }

    func testGeraSumarioQuandoNaoExiste() throws {
        let book = try EPUBParser.parse(data: try Fixtures.data("epubs/sem-nav.epub"))
        XCTAssertTrue(book.diagnostics.generatedNavigationFromHeadings)
        XCTAssertFalse(book.navigation.isEmpty)
        XCTAssertTrue(book.navigation.contains { $0.title == "Ensaio" })
    }

    func testRecusaConteudoProtegido() throws {
        XCTAssertThrowsError(try EPUBParser.parse(data: try Fixtures.data("epubs/com-drn.epub"))) { error in
            guard case EPUBError.protectedContent = error else {
                return XCTFail("Esperava EPUBError.protectedContent, obteve \(error)")
            }
        }
    }

    func testRecusaEpubSemContainer() throws {
        XCTAssertThrowsError(try EPUBParser.parse(data: try Fixtures.data("epubs/sem-container.epub"))) { error in
            XCTAssertEqual(error as? EPUBError, .missingContainer)
        }
    }

    func testRecusaArquivoCorrompido() throws {
        XCTAssertThrowsError(try EPUBParser.parse(data: try Fixtures.data("epubs/corrompido.epub")))
    }

    func testTextoExtraidoPermiteBuscaEDeteccaoDeReferencias() throws {
        let book = try EPUBParser.parse(data: try Fixtures.data("epubs/epub3-nav.epub"))
        let chapter = book.chapters[0]
        XCTAssertTrue(chapter.text.contains("Como preparar um discurso"))
        // Tags devem ser removidas do texto:
        XCTAssertFalse(chapter.text.contains("<p>"))

        let references = BibleReferenceParser.uniqueReferences(in: chapter.text)
        let displays = references.map(\.displayText)
        XCTAssertTrue(displays.contains("João 3:16"), "Referências encontradas: \(displays)")
        XCTAssertTrue(displays.contains("1 Coríntios 13:4-7"))
        XCTAssertTrue(displays.contains("Romanos 12:1, 2"))
    }

    func testScriptsSaoIgnoradosNaExtracao() throws {
        let book = try EPUBParser.parse(data: try Fixtures.data("epubs/epub3-nav.epub"))
        let chapter = book.chapters[1]
        XCTAssertFalse(chapter.text.contains("alert"))
        XCTAssertTrue(chapter.text.contains("Primeiro item de lista"))
    }

    func testIndiceDeTextoParaPesquisaLocal() throws {
        let book = try EPUBParser.parse(data: try Fixtures.data("epubs/epub3-nav.epub"))
        let itemID = UUID()
        let index = LibraryTextIndexBuilder.build(
            itemID: itemID,
            units: book.chapters.map { (title: $0.title, text: $0.text) }
        )
        XCTAssertEqual(index.chunks.count, 2)
        XCTAssertGreaterThan(index.totalWordCount, 40)

        let hits = LibrarySearch.search(query: "discurso", index: index, itemTitle: book.metadata.title)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.itemID, itemID)

        let empty = LibrarySearch.search(query: "zzzz-inexistente", index: index, itemTitle: book.metadata.title)
        XCTAssertTrue(empty.isEmpty)
    }

    func testNormalizacaoDeCaminhosInternos() {
        XCTAssertEqual(EPUPPath.normalize("OEBPS/./cap1.xhtml"), "OEBPS/cap1.xhtml")
        XCTAssertEqual(EPUPPath.normalize("OEBPS/texto/../cap1.xhtml"), "OEBPS/cap1.xhtml")
        XCTAssertEqual(EPUPPath.resolve(relativeTo: "OEBPS", path: "../imagens/capa.jpg"), "imagens/capa.jpg")
        XCTAssertEqual(EPUPPath.splitFragment("cap1.xhtml#secao").fragment, "secao")
        XCTAssertEqual(EPUPPath.fileExtension(of: "OEBPS/Cap1.XHTML"), "xhtml")
    }
}

final class HTMLTextExtractorTests: XCTestCase {

    func testExtraiTextoEBloqueiaScripts() {
        let html = """
        <html><head><title>Teste &amp; exemplo</title><style>p{color:red}</style></head>
        <body><h1>Título principal</h1><p>Primeiro parágrafo.</p>
        <script>var x = 1;</script><p>Segundo parágrafo com <b>negrito</b>.</p>
        <ul><li>Alfa</li><li>Beta</li></ul></body></html>
        """
        let extraction = HTMLTextExtractor.extract(from: html)
        XCTAssertEqual(extraction.title, "Teste & exemplo")
        XCTAssertTrue(extraction.text.contains("Título principal"))
        XCTAssertTrue(extraction.text.contains("Primeiro parágrafo."))
        XCTAssertTrue(extraction.text.contains("• Alfa"))
        XCTAssertFalse(extraction.text.contains("var x"))
        XCTAssertFalse(extraction.text.contains("color:red"))
        XCTAssertEqual(extraction.headings.first?.text, "Título principal")
        XCTAssertEqual(extraction.headings.first?.level, 1)
    }

    func testDecodificaEntidades() {
        XCTAssertEqual(HTMLTextExtractor.decodeEntities("João&nbsp;3:16 &amp; Salmo &#56;3:18"), "João\u{00A0}3:16 & Salmo 83:18")
        XCTAssertEqual(HTMLTextExtractor.decodeEntities("a&mdash;b &#x2014; c"), "a—b — c")
        XCTAssertEqual(HTMLTextExtractor.decodeEntities("&ccedil;&atilde;o"), "ção")
        XCTAssertEqual(HTMLTextExtractor.decodeEntities("sem entidade"), "sem entidade")
    }

    func testNaoQuebraComMarcacaoMalformada() {
        let html = "<p>Texto sem fechamento <b>negrito <div>mais texto"
        let extraction = HTMLTextExtractor.extract(from: html)
        XCTAssertTrue(extraction.text.contains("Texto sem fechamento"))
    }

    func testPreservaParagrafos() {
        let html = "<p>Um.</p><p>Dois.</p><p>Três.</p>"
        let extraction = HTMLTextExtractor.extract(from: html)
        XCTAssertEqual(extraction.paragraphs, ["Um.", "Dois.", "Três."])
    }
}
