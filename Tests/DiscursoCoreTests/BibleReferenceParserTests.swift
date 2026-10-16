//
//  BibleReferenceParserTests.swift
//  DiscursoCoreTests
//
//  Testes do reconhecimento de referências bíblicas.
//

import XCTest
@testable import DiscursoCore

final class BibleReferenceParserTests: XCTestCase {

    // MARK: - Exemplos do enunciado

    func testExemplosBasicosDoEnunciado() {
        let cases: [(String, Int, Int, String)] = [
            ("João 3:16", 43, 3, "3:16"),
            ("Mateus 24:14", 40, 24, "24:14"),
            ("Salmo 83:18", 19, 83, "83:18"),
            ("Romanos 12:1, 2", 45, 12, "12:1, 2"),
            ("1 Coríntios 13:4-7", 46, 13, "13:4-7"),
            ("Gênesis 1:1-3", 1, 1, "1:1-3")
        ]

        for (text, book, chapter, parts) in cases {
            let reference = BibleReferenceParser.parseWhole(text)
            XCTAssertNotNil(reference, "Não reconheceu: \(text)")
            XCTAssertEqual(reference?.bookID.rawValue, book, "Livro errado em: \(text)")
            XCTAssertEqual(reference?.primaryChapter, chapter, "Capítulo errado em: \(text)")
            XCTAssertEqual(reference?.partsDisplayText, parts, "Partes erradas em: \(text)")
        }
    }

    func testRomanosDozeUmDoisTemDoisVersiculosSeparados() {
        let reference = BibleReferenceParser.parseWhole("Romanos 12:1, 2")
        XCTAssertEqual(reference?.parts.count, 1)
        XCTAssertEqual(reference?.parts.first?.verses.count, 2)
        XCTAssertEqual(reference?.parts.first?.verses.first?.start, 1)
        XCTAssertEqual(reference?.parts.first?.verses.last?.start, 2)
    }

    func testUmCorintiosTrezeQuatroSeteEhUmaFaixa() {
        let reference = BibleReferenceParser.parseWhole("1 Coríntios 13:4-7")
        XCTAssertEqual(reference?.parts.first?.verses.count, 1)
        XCTAssertEqual(reference?.parts.first?.verses.first?.start, 4)
        XCTAssertEqual(reference?.parts.first?.verses.first?.end, 7)
    }

    // MARK: - Variações de escrita

    func testVariacoesDeAbreviacoesEAcentos() {
        let variations = [
            "Joao 3:16", "JOÃO 3:16", "joão 3:16", "Jo 3:16", "Joao 3.16", "João 3.16"
        ]
        for text in variations {
            let reference = BibleReferenceParser.parseWhole(text)
            XCTAssertEqual(reference?.bookID, BibleBookID.john, "Falhou em: \(text)")
            XCTAssertEqual(reference?.primaryChapter, 3)
            XCTAssertEqual(reference?.firstVerse, 16)
        }
    }

    func testAbreviacoesComPonto() {
        let cases: [(String, Int)] = [
            ("Mt. 24:14", 40),
            ("Gên. 1:1", 1),
            ("Sal. 83:18", 19),
            ("1 Cor. 13:4", 46),
            ("Ap. 21:4", 66),
            ("Êxo. 20:3", 2)
        ]
        for (text, book) in cases {
            XCTAssertEqual(BibleReferenceParser.parseWhole(text)?.bookID.rawValue, book, "Falhou em: \(text)")
        }
    }

    func testLivrosNumeradosComESemEspaco() {
        let cases: [(String, Int)] = [
            ("1 João 4:8", 62),
            ("1João 4:8", 62),
            ("1Jo 4:8", 62),
            ("2 João 1:2", 63),
            ("3 João 1:2", 64),
            ("2 Timóteo 3:16", 55),
            ("2Timóteo 3:16", 55),
            ("1 Tessalonicenses 5:17", 52),
            ("1ª Coríntios 13:4", 46),
            ("1º João 4:8", 62),
            ("I Coríntios 13:4", 46),
            ("II Coríntios 5:1", 47),
            ("III João 1:2", 64),
            ("Segunda Timóteo 3:16", 55),
            ("Primeira João 4:8", 62)
        ]
        for (text, book) in cases {
            XCTAssertEqual(BibleReferenceParser.parseWhole(text)?.bookID.rawValue, book, "Falhou em: \(text)")
        }
    }

    func testPalavrasChaveCapituloEVersiculo() {
        let cases: [(String, Int, Int, [Int])] = [
            ("João capítulo 3 versículo 16", 43, 3, [16]),
            ("João cap. 3 v. 16", 43, 3, [16]),
            ("João cap 3 vers 16, 17", 43, 3, [16, 17]),
            ("Salmo 83 versículos 18 a 20", 19, 83, [18, 19, 20])
        ]
        for (text, book, chapter, verses) in cases {
            let reference = BibleReferenceParser.parseWhole(text)
            XCTAssertEqual(reference?.bookID.rawValue, book, "Livro errado em: \(text)")
            XCTAssertEqual(reference?.primaryChapter, chapter, "Capítulo errado em: \(text)")
            XCTAssertEqual(reference?.parts.first?.verses.first?.start, verses.first, "Versículos errados em: \(text)")
        }
    }

    func testCapituloInteiro() {
        let reference = BibleReferenceParser.parseWhole("João 3")
        XCTAssertNotNil(reference)
        XCTAssertTrue(reference?.parts.first?.isWholeChapter ?? false)
        XCTAssertEqual(reference?.partsDisplayText, "3")
    }

    func testContinuacaoDeCapitulos() {
        let semicolon = BibleReferenceParser.parseWhole("João 3:16; 4:2")
        XCTAssertEqual(semicolon?.parts.count, 2)
        XCTAssertEqual(semicolon?.parts[0].chapter, 3)
        XCTAssertEqual(semicolon?.parts[0].verses.first?.start, 16)
        XCTAssertEqual(semicolon?.parts[1].chapter, 4)
        XCTAssertEqual(semicolon?.parts[1].verses.first?.start, 2)
        XCTAssertEqual(semicolon?.partsDisplayText, "3:16; 4:2")

        let comma = BibleReferenceParser.parseWhole("João 3:16, 4:2")
        XCTAssertEqual(comma?.parts.count, 2, "\"João 3:16, 4:2\" deve ter dois capítulos")
    }

    func testVersiculosParciais() {
        let reference = BibleReferenceParser.parseWhole("João 3:16a")
        XCTAssertEqual(reference?.parts.first?.verses.first?.suffix, "a")
        XCTAssertEqual(reference?.partsDisplayText, "3:16a")
    }

    func testListaLongaDeVersiculos() {
        let reference = BibleReferenceParser.parseWhole("Salmo 119:1-8, 105-112")
        XCTAssertEqual(reference?.parts.first?.verses.count, 2)
        XCTAssertEqual(reference?.totalVerses, 8 + 8)
    }

    // MARK: - Texto corrido

    func testVariasReferenciasNoMesmoParagrafo() {
        let text = "Em João 3:16 vemos o amor de Deus, e Romanos 5:8 confirma isso; também salmo 83:18 e Mateus 24:14 falam do assunto."
        let matches = BibleReferenceParser.matches(in: text)
        XCTAssertEqual(matches.count, 4)
        XCTAssertEqual(matches.map(\.reference.bookID.rawValue), [43, 45, 19, 40])
        // Os intervalos devem corresponder exatamente ao texto reconhecido.
        XCTAssertEqual(matches[0].matchedText, "João 3:16")
        XCTAssertEqual(matches[1].matchedText, "Romanos 5:8")
        XCTAssertEqual(matches[2].matchedText, "salmo 83:18")
        XCTAssertEqual(matches[3].matchedText, "Mateus 24:14")
    }

    func testIntervalosApontamParaOPosicaoCorretaNoTextoOriginal() {
        let text = "Leia Filipenses 4:6, 7 com atenção."
        guard let match = BibleReferenceParser.firstMatch(in: text) else {
            return XCTFail("Não reconheceu a referência")
        }
        XCTAssertEqual(match.matchedText, "Filipenses 4:6, 7")
        XCTAssertEqual(String(text[match.range]), "Filipenses 4:6, 7")
        XCTAssertEqual(match.reference.bookID.rawValue, 50)
    }

    func testNaoReconhecePalavrasParecidas() {
        let cases = [
            "Ele atordoava a todos com o barulho.",   // "at" dentro de palavra
            "Os irmãos na congregação",               // apelidos sem número de capítulo
            "Vamos ao mercado amanhã",
            "na 3 de janeiro",                        // apelido arriscado em minúscula
            "os 2:3",                                 // idem
            "Temos 4:2 de tempo"                      // "4:2" sem nome de livro
        ]
        for text in cases {
            XCTAssertTrue(BibleReferenceParser.matches(in: text).isEmpty, "Falso positivo em: \(text)")
        }
    }

    func testAceitaApelidoArriscadoComMaiuscula() {
        XCTAssertEqual(BibleReferenceParser.parseWhole("Na 3:1")?.bookID.rawValue, 34) // Naum
        XCTAssertEqual(BibleReferenceParser.parseWhole("Os 2:3")?.bookID.rawValue, 28) // Oseias
        XCTAssertEqual(BibleReferenceParser.parseWhole("At 2:1")?.bookID.rawValue, 44) // Atos
        XCTAssertEqual(BibleReferenceParser.parseWhole("Am 5:1")?.bookID.rawValue, 30) // Amós
        XCTAssertEqual(BibleReferenceParser.parseWhole("Is 41:10")?.bookID.rawValue, 23) // Isaías
        XCTAssertEqual(BibleReferenceParser.parseWhole("La 3:22")?.bookID.rawValue, 25) // Lamentações
    }

    func testJoAmbiguoEhResolvidoPeloAcento() {
        XCTAssertEqual(BibleReferenceParser.parseWhole("Jó 1:1")?.bookID.rawValue, 18)
        XCTAssertEqual(BibleReferenceParser.parseWhole("Jó 42:1")?.bookID.rawValue, 18)
        XCTAssertEqual(BibleReferenceParser.parseWhole("Jo 1:1")?.bookID.rawValue, 43)
        XCTAssertEqual(BibleReferenceParser.parseWhole("João 1:1")?.bookID.rawValue, 43)
        XCTAssertEqual(BibleReferenceParser.parseWhole("1 Jo 4:8")?.bookID.rawValue, 62)
    }

    func testRejeitaCapituloInexistente() {
        XCTAssertNil(BibleReferenceParser.parseWhole("João 25:1"), "João tem 21 capítulos")
        XCTAssertNil(BibleReferenceParser.parseWhole("Gênesis 51:1"), "Gênesis tem 50 capítulos")
        XCTAssertNil(BibleReferenceParser.parseWhole("Judas 2:1"), "Judas tem 1 capítulo")
        XCTAssertNil(BibleReferenceParser.parseWhole("Salmos 151:1"), "Salmos tem 150 capítulos")
        XCTAssertNotNil(BibleReferenceParser.parseWhole("Salmos 150:6"))
    }

    func testNaoConfundeVersiculoComNovoReferencia() {
        // "e 4:2" é um novo capítulo, não o versículo 4 da lista.
        let reference = BibleReferenceParser.parseWhole("João 3:16 e 4:2")
        XCTAssertEqual(reference?.parts.count, 2)
        XCTAssertEqual(reference?.parts[0].verses.first?.start, 16)
        XCTAssertEqual(reference?.parts[1].chapter, 4)
    }

    func testAceitaEComoSeparadorDeVersiculos() {
        let reference = BibleReferenceParser.parseWhole("Salmo 83:18 e 19")
        XCTAssertEqual(reference?.parts.first?.verses.count, 2)
    }

    func testReferenciaNoMeioDeTextoComPontuacao() {
        let text = "(Salmo 83:18); veja também: 1 Coríntios 13:4-7, 13."
        let matches = BibleReferenceParser.matches(in: text)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].matchedText, "Salmo 83:18")
        XCTAssertEqual(matches[1].matchedText, "1 Coríntios 13:4-7, 13")
        XCTAssertEqual(matches[1].reference.parts.first?.verses.count, 2)
    }

    func testParseWholeExigeTextoInteiro() {
        XCTAssertNil(BibleReferenceParser.parseWhole("João 3:16 e outras coisas"))
        XCTAssertNotNil(BibleReferenceParser.parseWhole("  João 3:16  "))
    }

    func testParsePrefix() {
        let result = BibleReferenceParser.parsePrefix("João 3:16 — o amor de Deus")
        XCTAssertEqual(result?.reference.bookID.rawValue, 43)
        XCTAssertEqual(result?.remainder, " — o amor de Deus")
    }

    func testUniqueReferencesRemoveRepeticoes() {
        let text = "João 3:16 ... e novamente João 3:16, mas também João 3:17."
        let unique = BibleReferenceParser.uniqueReferences(in: text)
        XCTAssertEqual(unique.count, 2)
        XCTAssertEqual(unique[0].partsDisplayText, "3:16")
        XCTAssertEqual(unique[1].partsDisplayText, "3:17")
    }

    func testTextoVazioENaoBiblico() {
        XCTAssertTrue(BibleReferenceParser.matches(in: "").isEmpty)
        XCTAssertTrue(BibleReferenceParser.matches(in: "Nenhuma referência aqui, apenas texto comum.").isEmpty)
        XCTAssertTrue(BibleReferenceParser.matches(in: "1234 5678 90:12").isEmpty)
    }

    func testDesempenhoComTextoLongo() {
        let paragraph = "Como vimos em João 3:16 e também em Salmo 83:18, precisamos continuar. "
        let text = String(repeating: paragraph, count: 200) // ~26 mil caracteres
        measure {
            let matches = BibleReferenceParser.matches(in: text)
            XCTAssertEqual(matches.count, 400)
        }
    }

    // MARK: - Formatação e links oficiais

    func testFormatacaoDeExibicao() {
        let reference = BibleReferenceParser.parseWhole("1 Coríntios 13:4-7")
        XCTAssertEqual(reference?.displayText, "1 Coríntios 13:4-7")
        XCTAssertEqual(reference?.abbreviatedText, "1 Cor. 13:4-7")
    }

    func testLinksOficiaisUsamNumeroDoLivro() {
        let reference = BibleReferenceParser.parseWhole("João 3:16")
        let url = reference?.officialWebURL()
        XCTAssertEqual(url?.absoluteString, "https://wol.jw.org/pt/wol/b/r5/lp-t/nwt/43/3#16")

        let chapter = BibleReferenceParser.parseWhole("Salmos 83")
        XCTAssertEqual(chapter?.officialWebURL()?.absoluteString, "https://wol.jw.org/pt/wol/b/r5/lp-t/nwt/19/83")
    }

    func testIdentificadoresDeVersiculoEPonteParaJWLibrary() {
        let reference = BibleReferenceParser.parseWhole("João 3:16")
        XCTAssertEqual(reference?.verseIdentifiers, ["43003016"])
        XCTAssertEqual(reference?.jwLibraryDeepLink()?.absoluteString, "jwlibrary:///finder?bible=43003016")
    }

    func testReferenciasRelacionadasApontamParaProximoCapitulo() {
        let reference = BibleReferenceParser.parseWhole("João 21:1")
        XCTAssertTrue(reference?.relatedChapterReferences.isEmpty ?? false, "João não tem capítulo 22")
        let salmos = BibleReferenceParser.parseWhole("Salmos 1:1")
        XCTAssertEqual(salmos?.relatedChapterReferences.first?.primaryChapter, 2)
    }
}
