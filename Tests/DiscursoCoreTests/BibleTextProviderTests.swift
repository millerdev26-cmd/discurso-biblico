//
//  BibleTextProviderTests.swift
//  DiscursoCoreTests
//
//  Testes da camada de texto bíblico:
//
//   - provedor de links oficiais (sem texto, sempre com link);
//   - provedor local (texto importado pelo usuário);
//   - referências inválidas, capítulos inteiros, versículos ausentes.
//
//  Nenhum texto bíblico real é usado: os versículos aqui são frases
//  inventadas para o teste, apenas para verificar a montagem do trecho.
//

import XCTest
@testable import DiscursoCore

final class OfficialLinkBibleProviderTests: XCTestCase {

    func testReferenciaValidaGeraLinksSemTexto() async throws {
        let provider = OfficialLinkBibleProvider()
        let reference = BibleReference(bookID: .john, chapter: 3, verseStart: 16)
        let passage = try await provider.passage(for: reference)

        XCTAssertTrue(passage.verses.isEmpty, "O provedor de links nunca devolve texto")
        XCTAssertEqual(passage.reference, reference)
        XCTAssertEqual(passage.officialURL?.absoluteString, "https://wol.jw.org/pt/wol/b/r5/lp-t/nwt/43/3#16")
        XCTAssertNotNil(passage.deepLink, "Oferece atalho para o JW Library quando instalado")
        XCTAssertNotNil(passage.notice, "Explica por que não há texto local")
        XCTAssertTrue(passage.missingVerseNumbers.isEmpty)
        XCTAssertTrue(passage.isEmpty)
    }

    func testCapituloInteiroNaoUsaAncoraDeVersiculo() async throws {
        let provider = OfficialLinkBibleProvider()
        let reference = BibleReference(bookID: .psalms, chapter: 23)
        let passage = try await provider.passage(for: reference)

        XCTAssertEqual(passage.officialURL?.absoluteString, "https://wol.jw.org/pt/wol/b/r5/lp-t/nwt/19/23")
        XCTAssertNil(passage.officialURL?.fragment)
        XCTAssertEqual(passage.deepLink?.query, "bible=19023001")
    }

    func testReferenciaInvalidaLancaErro() async {
        let provider = OfficialLinkBibleProvider()
        // João tem 21 capítulos; o 22 não existe.
        let reference = BibleReference(bookID: .john, chapter: 22)
        do {
            _ = try await provider.passage(for: reference)
            XCTFail("Deveria lançar invalidReference")
        } catch let error as BibleTextError {
            guard case .invalidReference(let text) = error else {
                return XCTFail("Esperava invalidReference, obteve \(error)")
            }
            XCTAssertEqual(text, "João 22")
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    func testIntervaloInvalidoLancaErro() async {
        let provider = OfficialLinkBibleProvider()
        // Intervalo invertido: 20-10.
        let part = BibleReferencePart(chapter: 3, verses: [BibleVerseRange(start: 20, end: 10)])
        let reference = BibleReference(bookID: .john, parts: [part])
        do {
            _ = try await provider.passage(for: reference)
            XCTFail("Deveria lançar invalidReference")
        } catch let error as BibleTextError {
            guard case .invalidReference = error else {
                return XCTFail("Esperava invalidReference, obteve \(error)")
            }
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }
}

final class LocalBibleTextProviderTests: XCTestCase {

    private func makeProvider(
        verses: [BibleBookID: [Int: [Int: String]]],
        sourceName: String = "Arquivo de teste"
    ) -> LocalBibleTextProvider {
        LocalBibleTextProvider(store: InMemoryBibleTextStore(verses: verses), sourceName: sourceName)
    }

    private let joaoCap3: [Int: [Int: String]] = [
        3: [
            16: "Versículo dezesseis de teste.",
            17: "Versículo dezessete de teste.",
            18: "Versículo dezoito de teste."
        ],
        4: [2: "Versículo dois do capítulo quatro."]
    ]

    func testServeVersiculosNaOrdemDaReferencia() async throws {
        let provider = makeProvider(verses: [.john: joaoCap3])
        let reference = BibleReference(
            bookID: .john,
            parts: [BibleReferencePart(chapter: 3, verses: [BibleVerseRange(start: 16, end: 17)])]
        )
        let passage = try await provider.passage(for: reference)

        XCTAssertEqual(passage.verses.map(\.number), [16, 17])
        XCTAssertEqual(passage.verses[0].text, "Versículo dezesseis de teste.")
        XCTAssertEqual(passage.sourceName, "Arquivo de teste")
        XCTAssertEqual(passage.officialURL?.absoluteString, "https://wol.jw.org/pt/wol/b/r5/lp-t/nwt/43/3#16")
        XCTAssertTrue(passage.missingVerseNumbers.isEmpty)
        XCTAssertNil(passage.notice)
        XCTAssertFalse(passage.isEmpty)
    }

    func testListaDeVersiculosEmTextoCorrido() async throws {
        let provider = makeProvider(verses: [.john: joaoCap3])
        let reference = BibleReference(
            bookID: .john,
            parts: [BibleReferencePart(chapter: 3, verses: [BibleVerseRange(start: 16), BibleVerseRange(start: 18)])]
        )
        let passage = try await provider.passage(for: reference)

        XCTAssertEqual(passage.verses.map(\.number), [16, 18])
        XCTAssertEqual(
            passage.plainText,
            "16 Versículo dezesseis de teste. 18 Versículo dezoito de teste."
        )
        XCTAssertEqual(passage.verse(number: 18)?.text, "Versículo dezoito de teste.")
        XCTAssertNil(passage.verse(number: 17))
    }

    func testVariasPartesEmOrdemDeLeitura() async throws {
        let provider = makeProvider(verses: [.john: joaoCap3])
        let reference = BibleReference(
            bookID: .john,
            parts: [
                BibleReferencePart(chapter: 3, verses: [BibleVerseRange(start: 16)]),
                BibleReferencePart(chapter: 4, verses: [BibleVerseRange(start: 2)])
            ]
        )
        let passage = try await provider.passage(for: reference)

        XCTAssertEqual(passage.verses.map(\.number), [16, 2], "A ordem é a da referência escrita")
        // Com mais de uma parte, o link aponta para o primeiro capítulo citado
        // sem âncora de versículo (comportamento de `officialWebURL`).
        XCTAssertEqual(passage.officialURL?.absoluteString, "https://wol.jw.org/pt/wol/b/r5/lp-t/nwt/43/3")
    }

    func testCapituloInteiroDevolveTodosOsVersiculosDisponiveis() async throws {
        let provider = makeProvider(verses: [.john: joaoCap3])
        let reference = BibleReference(bookID: .john, chapter: 3)
        let passage = try await provider.passage(for: reference)

        XCTAssertEqual(passage.verses.map(\.number), [16, 17, 18], "Números em ordem crescente")
        XCTAssertTrue(passage.missingVerseNumbers.isEmpty)
        XCTAssertNil(passage.notice)
    }

    func testVersiculoAusenteViraAvisoENaoInterrompe() async throws {
        let provider = makeProvider(verses: [.john: joaoCap3])
        let reference = BibleReference(
            bookID: .john,
            parts: [BibleReferencePart(chapter: 3, verses: [BibleVerseRange(start: 16), BibleVerseRange(start: 20)])]
        )
        let passage = try await provider.passage(for: reference)

        XCTAssertEqual(passage.verses.map(\.number), [16])
        XCTAssertEqual(passage.missingVerseNumbers, [20])
        let notice = try XCTUnwrap(passage.notice)
        XCTAssertTrue(notice.contains("20"), "O aviso lista os versículos não encontrados")
    }

    func testTextoVazioEtratadoComoAusente() async throws {
        let provider = makeProvider(verses: [.john: [3: [16: "  ", 17: "Versículo de teste.", 18: ""]]])
        let reference = BibleReference(
            bookID: .john,
            parts: [BibleReferencePart(chapter: 3, verses: [BibleVerseRange(start: 16, end: 17)])]
        )
        let passage = try await provider.passage(for: reference)

        XCTAssertEqual(passage.verses.map(\.number), [17])
        XCTAssertEqual(passage.missingVerseNumbers, [16])

        // O mesmo vale para capítulo inteiro: versículos só com espaços são
        // omitidos em vez de aparecerem vazios.
        let wholeChapter = try await provider.passage(for: BibleReference(bookID: .john, chapter: 3))
        XCTAssertEqual(wholeChapter.verses.map(\.number), [17])
    }

    func testCapituloSemTextoNoArquivoLancaTextoIndisponivel() async {
        let provider = makeProvider(verses: [.john: joaoCap3])
        let reference = BibleReference(bookID: .john, chapter: 10)
        do {
            _ = try await provider.passage(for: reference)
            XCTFail("Deveria lançar textUnavailable")
        } catch let error as BibleTextError {
            guard case .textUnavailable(let text) = error else {
                return XCTFail("Esperava textUnavailable, obteve \(error)")
            }
            XCTAssertEqual(text, "João 10")
            XCTAssertNotNil(error.recoverySuggestion, "Orienta o usuário a usar o link oficial ou importar texto")
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    func testReferenciaInvalidaLancaErro() async {
        let provider = makeProvider(verses: [.john: joaoCap3])
        let reference = BibleReference(bookID: .john, parts: [])
        do {
            _ = try await provider.passage(for: reference)
            XCTFail("Deveria lançar invalidReference")
        } catch let error as BibleTextError {
            guard case .invalidReference = error else {
                return XCTFail("Esperava invalidReference, obteve \(error)")
            }
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    func testArmazenamentoEmMemoriaAceitaOsDoisFormatos() async {
        let typed = InMemoryBibleTextStore(verses: [.john: [3: [16: "Texto."]]])
        let versesByKey = await typed.verses(bookID: .john, chapter: 3)
        XCTAssertEqual(versesByKey[16], "Texto.")

        let raw = InMemoryBibleTextStore(texts: ["43-3": [16: "Texto."]])
        let rawVerses = await raw.verses(bookID: .john, chapter: 3)
        XCTAssertEqual(rawVerses[16], "Texto.")

        let empty = await raw.verses(bookID: .john, chapter: 4)
        XCTAssertTrue(empty.isEmpty)
    }

    func testVersiculoComSufixoParcialEUsadoComoUmInteiro() async throws {
        // "João 3:16a" cita o versículo 16 inteiro no arquivo importado.
        let provider = makeProvider(verses: [.john: joaoCap3])
        let part = BibleReferencePart(
            chapter: 3,
            verses: [BibleVerseRange(start: 16, suffix: "a")]
        )
        let passage = try await provider.passage(for: BibleReference(bookID: .john, parts: [part]))
        XCTAssertEqual(passage.verses.map(\.number), [16])
    }
}
