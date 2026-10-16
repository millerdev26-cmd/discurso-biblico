//
//  DemoSeedTests.swift
//  DiscursoBiblicoTests
//
//  Testes dos dados de exemplo usados pelos testes de interface: eles
//  garantem que o conteúdo semeado exercita o que as capturas de tela
//  precisam mostrar (marcações, referências, notas, listas e um material
//  indexável na biblioteca).
//
//  O conteúdo (DemoSeed.swift) é Swift puro, então estes testes também rodam
//  na verificação em Linux (Scripts/verify_app_logic.sh); a instalação no
//  banco é exercitada pelos testes de interface no simulador.
//

import DiscursoCore
import XCTest
@testable import DiscursoBiblico

final class DemoSeedTests: XCTestCase {

    // MARK: - Discurso de exemplo

    func testDiscursoDeExemploCobreOsTiposDeConteudo() {
        let speech = DemoSeed.makeSpeech()

        XCTAssertEqual(speech.sections.count, 4)
        XCTAssertEqual(speech.sections.map(\.title), [
            "Introdução",
            "Desenvolvimento 1 — a base da esperança",
            "Desenvolvimento 2 — como isso alcança o ouvinte",
            "Conclusão"
        ])

        let kinds = Set(speech.allBlocks.map(\.kind))
        for expected in [SpeechBlockKind.heading, .paragraph, .note, .cue, .bulletList, .quote] {
            XCTAssertTrue(
                kinds.contains(expected),
                "O exemplo não tem bloco do tipo \(expected.displayName)."
            )
        }
    }

    func testDiscursoDeExemploTrazReferenciasENotas() {
        let speech = DemoSeed.makeSpeech()
        let references = speech.references.map(\.displayText)

        // O texto do exemplo escreve "Salmo 23:1-4" (singular, como se fala),
        // mas a referência é exibida com o nome canônico do catálogo: "Salmos".
        XCTAssertTrue(references.contains("João 3:16"))
        XCTAssertTrue(references.contains("Salmos 23:1-4"))
        XCTAssertTrue(references.contains("Romanos 15:13"))
        XCTAssertTrue(references.contains("Colossenses 3:13"))

        XCTAssertFalse(
            speech.sections.flatMap(\.blocks).filter(\.isPresenterNote).isEmpty,
            "O exemplo precisa de pelo menos uma nota do apresentador."
        )
    }

    func testDiscursoDeExemploNaoMostraMarcacoesNoTextoProferido() {
        let speech = DemoSeed.makeSpeech()
        let text = speech.plainText(includePresenterNotes: false)

        XCTAssertTrue(text.contains("Boa noite a todos"))
        XCTAssertFalse(text.contains("{"), "As marcações de orador vazaram no texto proferido.")
        XCTAssertFalse(text.contains("}"), "As marcações de orador vazaram no texto proferido.")
        XCTAssertFalse(text.contains("*"), "A marcação de ênfase vazou no texto proferido.")
    }

    func testDiscursoDeExemploTemConteudoParaProferir() {
        let speech = DemoSeed.makeSpeech()

        XCTAssertEqual(speech.displayTitle, "Discurso de exemplo — João 3:16")
        XCTAssertEqual(speech.plannedMinutes, 30)
        XCTAssertGreaterThan(speech.wordCount, 100)
    }

    // MARK: - Material de biblioteca

    func testMaterialDeExemploTemTitulosParaOIndice() {
        let lines = DemoSeed.markdown.split(separator: "\n").map(String.init)
        let headings = lines.filter { $0.hasPrefix("#") }

        XCTAssertGreaterThanOrEqual(headings.count, 4, "O índice precisa de títulos para dividir o material.")
        XCTAssertTrue(DemoSeed.markdown.contains("Anotações de estudo"))
        XCTAssertTrue(DemoSeed.markdown.contains("João 3:16"))
    }
}
