//
//  InlineMarkupTests.swift
//  DiscursoCoreTests
//
//  Testes das marcações em linha (*ênfase*, {pausa}, {tom: ...}, {nota: ...}).
//
//  Regressões cobertas (defeitos encontrados na primeira execução no iOS):
//   - o texto exibido dos segmentos deve sair do texto **original** (com
//     acentos e maiúsculas), não da versão normalizada usada para reconhecer
//     as palavras-chave — o defeito transformava "*João 3:16*" em "joao 3:16"
//     na exportação e no modo de proferimento;
//   - `plainText` remove as marcações sem deixar espaços duplos.
//

import XCTest
@testable import DiscursoCore

final class InlineMarkupTests: XCTestCase {

    // MARK: - Texto simples

    func testTextoComEnfaseMantemAcentosEMaiusculas() {
        let text = "Boa noite a todos. Vamos ler *João 3:16* e refletir {pausa: 2} sobre isso."
        let plain = InlineMarkup.plainText(text)
        XCTAssertEqual(plain, "Boa noite a todos. Vamos ler João 3:16 e refletir sobre isso.")
    }

    func testSegmentoDeEnfaseTrazOTextoOriginal() {
        let text = "Leia *Gênesis 1:1* com atenção."
        let emphasis = InlineMarkup.segments(in: text, detectReferences: false)
            .first { $0.isEmphasized }
        XCTAssertEqual(emphasis?.text, "Gênesis 1:1")
    }

    func testSegmentosCobremOTextoInteiroNaOrdem() {
        let text = "Início *meio* fim {pausa}."
        let segments = InlineMarkup.segments(in: text, detectReferences: false)

        var cursor = text.startIndex
        for segment in segments {
            XCTAssertEqual(segment.range.lowerBound, cursor, "Os segmentos devem ser contíguos")
            cursor = segment.range.upperBound
        }
        XCTAssertEqual(cursor, text.endIndex, "Os segmentos devem cobrir o texto inteiro")
        XCTAssertEqual(segments.map(\.text).joined(), "Início meio fim pausa.")
    }

    // MARK: - Observações privadas

    func testNotaPrivadaMantemOTextoOriginal() {
        let text = "Falar devagar {nota: Revisar a Introdução}"
        let note = InlineMarkup.segments(in: text, detectReferences: false)
            .first { $0.isPrivateNote }
        XCTAssertEqual(note?.text, "Revisar a Introdução")
        XCTAssertEqual(InlineMarkup.plainText(text), "Falar devagar")
    }

    // MARK: - Indicações

    func testDetalheDaIndicacaoMantemAMaiuscula() {
        let text = "{tom: Solene} e depois {pausa: 3}"
        let segments = InlineMarkup.segments(in: text, detectReferences: false)
        let tone = segments.first { $0.cue == .toneChange }
        XCTAssertEqual(tone?.cueDetail, "Solene")

        let pause = segments.first { $0.cue == .pause }
        XCTAssertEqual(pause?.cueDetail, "3")
        XCTAssertEqual(InlineMarkup.plainText(text), "e depois")
    }

    func testResumoContaIndicacoesEPausasExplicitas() {
        let summary = InlineMarkup.summary(of: "A {pausa: 3}{pausa: 2} B {tom: solene}")
        XCTAssertEqual(summary.count(of: .pause), 2)
        XCTAssertEqual(summary.count(of: .toneChange), 1)
        XCTAssertEqual(summary.explicitPauseSeconds, 5, accuracy: 0.001)
    }

    // MARK: - Referências

    func testReferenciaBiblicaMantemOTextoOriginal() {
        let text = "Vamos ler João 3:16 agora."
        let reference = InlineMarkup.segments(in: text).first { $0.reference != nil }
        XCTAssertEqual(reference?.text, "João 3:16")
        XCTAssertEqual(reference?.reference?.primaryChapter, 3)
    }

    // MARK: - Detecção

    func testContainsMarkupReconheceAsMarcacoes() {
        XCTAssertTrue(InlineMarkup.containsMarkup("Olá *mundo*"))
        XCTAssertTrue(InlineMarkup.containsMarkup("Espere {pausa}"))
        XCTAssertFalse(InlineMarkup.containsMarkup("Texto comum, 100% claro"))
    }
}
