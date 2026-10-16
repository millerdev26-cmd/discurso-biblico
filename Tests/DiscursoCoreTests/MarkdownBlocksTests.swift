//
//  MarkdownBlocksTests.swift
//  DiscursoCoreTests
//
//  Interpretação de Markdown em blocos, usada pelo leitor interno da
//  biblioteca (o defeito que motivou o arquivo: o leitor mostrava "# Título"
//  e "- item" crus na tela).
//

import XCTest
@testable import DiscursoCore

final class MarkdownBlocksTests: XCTestCase {

    // MARK: - Estrutura

    func testTituloParagrafoELista() {
        let markdown = """
        # Anotações de estudo

        Este material reúne ideias para a semana.

        ## Esperança que se apoia em promessas

        - João 3:16 — amor que age.
        - Salmo 23:1-4 — cuidado.
        """

        let blocks = MarkdownBlocks.parse(markdown)

        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Anotações de estudo"),
            .paragraph("Este material reúne ideias para a semana."),
            .heading(level: 2, text: "Esperança que se apoia em promessas"),
            .listItem(marker: .bullet, text: "João 3:16 — amor que age."),
            .listItem(marker: .bullet, text: "Salmo 23:1-4 — cuidado.")
        ])
    }

    func testListaNumeradaPreservaONumero() {
        let blocks = MarkdownBlocks.parse("""
        1. Abra o material na Biblioteca.
        2) Alternativa com parêntese.
        3. Terceiro item.
        """)

        XCTAssertEqual(blocks, [
            .listItem(marker: .number(1), text: "Abra o material na Biblioteca."),
            .listItem(marker: .number(2), text: "Alternativa com parêntese."),
            .listItem(marker: .number(3), text: "Terceiro item.")
        ])
    }

    func testCitacaoLinhaHorizontalECodigo() {
        let blocks = MarkdownBlocks.parse("""
        > A esperança é a âncora.

        ---

        ```swift
        let x = 1
        // # não é título dentro do código
        ```
        """)

        XCTAssertEqual(blocks, [
            .quote("A esperança é a âncora."),
            .rule,
            .code("let x = 1\n// # não é título dentro do código")
        ])
    }

    // MARK: - Marcação embutida

    func testMarcacaoEmbutidaSomeDoTexto() {
        let blocks = MarkdownBlocks.parse(
            "Veja **a parte principal**, *o detalhe* e o `código` de [a fonte](https://exemplo.org)."
        )

        XCTAssertEqual(blocks, [
            .paragraph("Veja a parte principal, o detalhe e o código de a fonte (https://exemplo.org).")
        ])
    }

    func testImagemViraTextoAlternativo() {
        let blocks = MarkdownBlocks.parse("![Diagrama da promessa](https://exemplo.org/a.png)")

        XCTAssertEqual(blocks, [.paragraph("Diagrama da promessa")])
    }

    // MARK: - Robustez

    func testLinhasVaziasJuntamParagrafo() {
        let blocks = MarkdownBlocks.parse("""
        Primeira linha
        continua na segunda.
        Terceiro parágrafo depois da linha vazia.
        """)

        XCTAssertEqual(blocks, [
            .paragraph("Primeira linha continua na segunda. Terceiro parágrafo depois da linha vazia.")
        ])
    }

    func testCercaDeCodigoSemFechamentoNaoPerdeOTexto() {
        let blocks = MarkdownBlocks.parse("""
        Antes

        ```
        texto solto
        """)

        XCTAssertEqual(blocks, [
            .paragraph("Antes"),
            .code("texto solto")
        ])
    }

    func testSeteCaretasNaoViramTitulo() {
        // Sete `#` não são título em Markdown: a linha continua texto, com os
        // caracteres preservados (nada some da tela).
        let blocks = MarkdownBlocks.parse("####### Sete níveis não são título")

        XCTAssertEqual(blocks, [.paragraph("####### Sete níveis não são título")])
    }

    func testMarcadorSoNaoSomeDaTela() {
        // "- " sem conteúdo não é item de lista; o texto segue legível.
        let blocks = MarkdownBlocks.parse("- \ntexto solto")

        XCTAssertEqual(MarkdownBlocks.plainText(from: blocks), "- texto solto")
    }

    func testTipoDeCadaBloco() {
        let blocks = MarkdownBlocks.parse("""
        # Título

        texto

        - item
        > citação
        ---
        ```
        código
        ```
        """)

        XCTAssertEqual(blocks.map(\.kind), [
            .heading, .paragraph, .listItem, .quote, .rule, .code
        ])
    }

    func testTextoSimplesNaoMuda() {
        let texto = "Uma nota qualquer.\nOutra linha da mesma nota."

        let blocks = MarkdownBlocks.parse(texto)

        XCTAssertEqual(blocks, [.paragraph(texto.replacingOccurrences(of: "\n", with: " "))])
    }

    // MARK: - Texto simples

    func testTextoSimplesIgnoraAFormatacao() {
        let markdown = """
        # Título

        - primeiro
        2. segundo

        > citação
        """

        XCTAssertEqual(
            MarkdownBlocks.plainText(from: MarkdownBlocks.parse(markdown)),
            "Título\n• primeiro\n2. segundo\ncitação"
        )
    }
}