//
//  LibraryFileStoreTests.swift
//  DiscursoBiblicoTests
//
//  Testes do armazenamento em disco dos arquivos da biblioteca
//  (`<Suporte do app>/Library/files/<id>.<ext>`).
//

import DiscursoCore
import Foundation
import XCTest
@testable import DiscursoBiblico

final class LibraryFileStoreTests: XCTestCase {

    private var root: URL!
    private var store: LibraryFileStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = AppTestSupport.makeTemporaryDirectory()
        store = LibraryFileStore(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        if let root { AppTestSupport.remove(root) }
        root = nil
        store = nil
        try super.tearDownWithError()
    }

    // MARK: Nomes e caminhos

    func testNomeDoArquivoUsaOIdentificadorEAExtensãoMinúscula() {
        let id = UUID()
        let url = store.fileURL(itemID: id, fileExtension: "EPUB")
        XCTAssertEqual(url.lastPathComponent, "\(id.uuidString).epub")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, root.standardizedFileURL)
    }

    func testExtensãoVaziaNãoCriaPontoFinal() {
        let id = UUID()
        let url = store.fileURL(itemID: id, fileExtension: "")
        XCTAssertEqual(url.lastPathComponent, id.uuidString)
    }

    func testCaminhoDoMaterialVemDoPróprioItem() {
        let item = AppSpeechFactory.makeLibraryItem()
        XCTAssertEqual(store.fileURL(for: item).lastPathComponent, "\(item.id.uuidString).txt")
    }

    // MARK: Gravação

    func testGuardaLêESubstituiArquivo() throws {
        let id = UUID()
        XCTAssertFalse(store.fileExists(for: AppSpeechFactory.makeLibraryItem(id: id)))

        let firstName = try store.store(data: Data("primeira versão".utf8), itemID: id, fileExtension: "txt")
        XCTAssertEqual(firstName, "\(id.uuidString).txt")

        let url = store.fileURL(itemID: id, fileExtension: "txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "primeira versão")

        // Reindexação: guardar de novo substitui o conteúdo anterior.
        try store.store(data: Data("segunda versão".utf8), itemID: id, fileExtension: "txt")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "segunda versão")
    }

    func testGuardaCopiaDeUmArquivoEscolhidoPeloUsuário() throws {
        let id = UUID()
        let source = try AppTestSupport.writeFile(named: "origem.txt", contents: "conteúdo importado", in: root)

        let fileName = try store.store(copying: source, itemID: id, fileExtension: "txt")
        XCTAssertEqual(fileName, "\(id.uuidString).txt")

        let destination = store.fileURL(itemID: id, fileExtension: "txt")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "conteúdo importado")
        // O original continua onde estava.
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testArquivoDeOrigemInexistenteFalhaSemCriarDestino() {
        let id = UUID()
        let missing = root.appendingPathComponent("não-existe.txt")
        XCTAssertThrowsError(try store.store(copying: missing, itemID: id, fileExtension: "txt"))
        XCTAssertFalse(store.fileExists(for: AppSpeechFactory.makeLibraryItem(id: id)))
    }

    // MARK: Remoção

    func testRemoveArquivoDoMaterial() throws {
        let id = UUID()
        try store.store(data: Data("conteúdo".utf8), itemID: id, fileExtension: "txt")
        let item = AppSpeechFactory.makeLibraryItem(id: id)
        XCTAssertTrue(store.fileExists(for: item))

        store.removeFile(for: item)
        XCTAssertFalse(store.fileExists(for: item))

        // Remover de novo não quebra nada.
        store.removeFile(for: item)
    }

    func testMateriaisDiferentesNãoColidem() throws {
        let first = UUID()
        let second = UUID()
        try store.store(data: Data("um".utf8), itemID: first, fileExtension: "txt")
        try store.store(data: Data("dois".utf8), itemID: second, fileExtension: "txt")

        XCTAssertEqual(
            try String(contentsOf: store.fileURL(itemID: first, fileExtension: "txt"), encoding: .utf8),
            "um"
        )
        XCTAssertEqual(
            try String(contentsOf: store.fileURL(itemID: second, fileExtension: "txt"), encoding: .utf8),
            "dois"
        )
    }
}
