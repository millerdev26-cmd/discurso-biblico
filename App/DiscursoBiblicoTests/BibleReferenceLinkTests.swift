//
//  BibleReferenceLinkTests.swift
//  DiscursoBiblicoTests
//
//  Testes das ligações internas de referências bíblicas
//  (`discursoref://43/3/16`), usadas para abrir o painel do trecho por cima
//  do discurso sem perder a posição de leitura.
//

import DiscursoCore
import Foundation
import XCTest
@testable import DiscursoBiblico

final class BibleReferenceLinkTests: XCTestCase {

    // MARK: Montagem

    func testLigaçãoDeVersículoÚnico() throws {
        let reference = BibleReference(bookID: .john, chapter: 3, verseStart: 16)
        let url = try XCTUnwrap(BibleReferenceLink.url(for: reference))
        XCTAssertEqual(url.host, "43")
        XCTAssertEqual(url.path, "/3/16")
        XCTAssertEqual(BibleReferenceLink.reference(from: url), reference)
    }

    func testLigaçãoDeFaixaDeVersículos() throws {
        let reference = BibleReference(bookID: .john, chapter: 3, verseStart: 16, verseEnd: 17)
        let url = try XCTUnwrap(BibleReferenceLink.url(for: reference))
        XCTAssertEqual(url.path, "/3/16-17")
        XCTAssertEqual(BibleReferenceLink.reference(from: url), reference)
    }

    func testLigaçãoDeCapítuloInteiro() throws {
        let reference = BibleReference(bookID: .psalms, chapter: 23)
        let url = try XCTUnwrap(BibleReferenceLink.url(for: reference))
        XCTAssertEqual(url.host, "19")
        XCTAssertEqual(url.path, "/23")
        XCTAssertEqual(BibleReferenceLink.reference(from: url), reference)
    }

    func testIdaEVoltaParaTodosOsLivros() throws {
        for ordinal in 1...66 {
            let bookID = BibleBookID(rawValue: ordinal)
            let reference = BibleReference(bookID: bookID, chapter: 1, verseStart: 1)
            let url = try XCTUnwrap(BibleReferenceLink.url(for: reference), "Livro \(ordinal) sem ligação")
            XCTAssertEqual(
                BibleReferenceLink.reference(from: url),
                reference,
                "Ida e volta falhou para o livro \(ordinal) (\(BibleBookCatalog.displayName(for: bookID)))"
            )
        }
    }

    func testReferênciaComVáriosTrechosUsaOPrimeiroNoToque() throws {
        // A ligação destaca um trecho por vez; o primeiro é o que abre.
        let reference = BibleReference(bookID: BibleBookID(rawValue: 40), parts: [
            BibleReferencePart(chapter: 5, verses: [BibleVerseRange(start: 3, end: 5)]),
            BibleReferencePart(chapter: 6, verses: [BibleVerseRange(start: 9)])
        ])
        let url = try XCTUnwrap(BibleReferenceLink.url(for: reference))
        XCTAssertEqual(url.path, "/5/3-5")
        XCTAssertEqual(
            BibleReferenceLink.reference(from: url),
            BibleReference(bookID: BibleBookID(rawValue: 40), chapter: 5, verseStart: 3, verseEnd: 5)
        )
    }

    // MARK: Interpretação

    func testEndereçosDeOutrosEsquemasSãoIgnorados() throws {
        XCTAssertNil(BibleReferenceLink.reference(from: try XCTUnwrap(URL(string: "https://wol.jw.org/pt/wol/b/r5/lp-t/nwt/43/3#16"))))
        XCTAssertNil(BibleReferenceLink.reference(from: try XCTUnwrap(URL(string: "discursoref://"))))
        XCTAssertNil(BibleReferenceLink.reference(from: try XCTUnwrap(URL(string: "discursoref://abc/3"))))
    }

    func testLivroForaDaFaixaÉIgnorado() throws {
        XCTAssertNil(BibleReferenceLink.reference(from: try XCTUnwrap(URL(string: "discursoref://0/1"))))
        XCTAssertNil(BibleReferenceLink.reference(from: try XCTUnwrap(URL(string: "discursoref://67/1"))))
    }

    func testCapítuloAusenteOuInválidoÉIgnorado() throws {
        XCTAssertNil(BibleReferenceLink.reference(from: try XCTUnwrap(URL(string: "discursoref://43/"))))
        XCTAssertNil(BibleReferenceLink.reference(from: try XCTUnwrap(URL(string: "discursoref://43/abc"))))
    }

    func testVersículoMalFormadoVoltaComoCapítuloInteiro() throws {
        for path in ["/3/", "/3/-", "/3/texto"] {
            let url = try XCTUnwrap(URL(string: "discursoref://43\(path)"))
            XCTAssertEqual(
                BibleReferenceLink.reference(from: url),
                BibleReference(bookID: .john, chapter: 3),
                "Caminho \(path) deveria ser tratado como capítulo inteiro"
            )
        }
    }

    func testFaixasParciaisSãoAceitasComOValorDisponível() throws {
        let openEnded = try XCTUnwrap(URL(string: "discursoref://43/3/16-"))
        XCTAssertEqual(
            BibleReferenceLink.reference(from: openEnded),
            BibleReference(bookID: .john, chapter: 3, verseStart: 16, verseEnd: 16)
        )

        let extraPiece = try XCTUnwrap(URL(string: "discursoref://43/3/16-18-20"))
        XCTAssertEqual(
            BibleReferenceLink.reference(from: extraPiece),
            BibleReference(bookID: .john, chapter: 3, verseStart: 16, verseEnd: 18)
        )
    }

    // MARK: Integração com o texto do discurso

    func testTodosOsTrechosReconhecidosNoTextoGanhamLigaçãoVálida() {
        let text = "Vamos ler João 3:16; Salmos 23; Filipenses 4:6, 7 e também Gênesis 1:1-5."
        let references = BibleReferenceParser.uniqueReferences(in: text)
        XCTAssertFalse(references.isEmpty)

        for reference in references {
            guard let url = BibleReferenceLink.url(for: reference) else {
                return XCTFail("Sem ligação para \(reference.displayText)")
            }
            let parsed = BibleReferenceLink.reference(from: url)
            XCTAssertNotNil(parsed, "A ligação \(url.absoluteString) não pôde ser interpretada")
            XCTAssertEqual(parsed?.bookID, reference.bookID)
            XCTAssertEqual(parsed?.primaryChapter, reference.primaryChapter)
        }
    }
}
