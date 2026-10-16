//
//  DiscursoBiblicoUITests.swift
//  DiscursoBiblicoUITests
//
//  Testes de interface no simulador (CI).
//
//  Estes testes navegam pelo aplicativo de verdade e guardam capturas de tela
//  como anexos do resultado dos testes; o workflow do GitHub Actions extrai e
//  publica essas imagens (artefato "capturas-simulador"). É assim que o
//  projeto é conferido visualmente sem depender de um Mac.
//
//  O conteúdo de exemplo é criado pelo próprio aplicativo quando iniciado com
//  o argumento "-uiTestSeed" (ver DemoSeed.swift): um discurso com marcações,
//  referências, notas e indicações, além de um material indexado na
//  biblioteca. Sem o argumento, nada disso é criado.
//

import XCTest

final class DiscursoBiblicoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Discursos: lista, detalhe, editor e proferimento

    @MainActor
    func testDiscursoDetalheEditorEProferimento() throws {
        let app = launchSeededApp()

        // 1. Lista de discursos ("Continuar" e o discurso de exemplo).
        let row = speechRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 15), "O discurso de exemplo não apareceu na lista.")
        capture(named: "01-lista-de-discursos")
        row.tap()

        // 2. Detalhe do discurso.
        let present = app.navigationBars.buttons["Abrir no modo de proferimento"]
        XCTAssertTrue(present.waitForExistence(timeout: 60), "A tela de detalhe do discurso não abriu.")
        Thread.sleep(forTimeInterval: 1.5)
        capture(named: "02-detalhe-do-discurso")

        // 3. Editor.
        app.navigationBars.buttons["Editar discurso"].tap()
        let editorDone = app.buttons["Pronto"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: 60), "O editor do discurso não abriu.")
        Thread.sleep(forTimeInterval: 1.5)
        capture(named: "03-editor-do-discurso")
        editorDone.tap()

        // 4. Modo de proferimento (a tela limpa, sem controles).
        XCTAssertTrue(present.waitForExistence(timeout: 30), "A tela de detalhe não voltou.")
        present.tap()

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 90), "O modo de proferimento não abriu.")
        Thread.sleep(forTimeInterval: 2.5)
        if let conteudo = textView.value as? String {
            XCTAssertTrue(
                conteudo.contains("Boa noite"),
                "O texto do discurso não apareceu na apresentação (início: \(conteudo.prefix(120)))."
            )
        }
        capture(named: "04-proferimento")

        // 5. Um toque no meio da tela revela os controles.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let settings = app.buttons["Ajustes da apresentação"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "Os controles da apresentação não apareceram.")
        capture(named: "05-proferimento-com-controles")

        // 6. Ajustes da apresentação (texto, tema, espaçamento).
        settings.tap()
        let settingsDone = app.buttons["Pronto"]
        XCTAssertTrue(settingsDone.waitForExistence(timeout: 30), "Os ajustes da apresentação não abriram.")
        Thread.sleep(forTimeInterval: 1.5)
        capture(named: "06-ajustes-da-apresentacao")
        settingsDone.tap()

        // 7. Texto maior e salto para o próximo tópico.
        let bigger = app.buttons["Aumentar o texto"]
        if bigger.waitForExistence(timeout: 15) {
            bigger.tap()
            bigger.tap()
            Thread.sleep(forTimeInterval: 1)
            capture(named: "07-proferimento-texto-maior")

            app.buttons["Próximo tópico"].tap()
            Thread.sleep(forTimeInterval: 2.5)
            capture(named: "08-proximo-topico")
        }
    }

    // MARK: - Biblioteca, leitura e demais abas

    @MainActor
    func testBibliotecaLeituraEPesquisa() throws {
        let app = launchSeededApp()

        // 1. Biblioteca com o material de exemplo.
        app.tabBars.buttons["Biblioteca"].tap()
        let item = libraryRow(in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 30), "O material de exemplo não apareceu na biblioteca.")
        capture(named: "09-biblioteca")
        item.tap()

        // 2. Leitura interna do material (texto extraído e indexado).
        Thread.sleep(forTimeInterval: 3)
        capture(named: "10-leitura-do-material")

        // 3. Volta e mostra as demais abas.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Pesquisar"].tap()
        Thread.sleep(forTimeInterval: 2)
        capture(named: "11-pesquisar")

        app.tabBars.buttons["Ajustes"].tap()
        Thread.sleep(forTimeInterval: 2)
        capture(named: "12-ajustes")
    }

    // MARK: - Apoio

    /// Abre o aplicativo com os dados de exemplo.
    private func launchSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(launchArgument)
        app.launch()
        XCTAssertTrue(
            app.tabBars.buttons["Discursos"].waitForExistence(timeout: 120),
            "O aplicativo não abriu a tela principal."
        )
        return app
    }

    /// Guarda uma captura da tela inteira como anexo do resultado.
    private func capture(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Linha da lista de discursos que contém o exemplo.
    ///
    /// A primeira célula pode ser a linha "Continuar", que abre direto o modo
    /// de proferimento; a linha da lista é identificada pela ausência desse
    /// prefixo (as células combinam o texto dos filhos em um único rótulo).
    private func speechRow(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(
            format: "label CONTAINS %@ AND NOT (label CONTAINS %@)",
            "Discurso de exemplo",
            "Continuar:"
        )
        let cell = app.cells.matching(predicate).firstMatch
        if cell.waitForExistence(timeout: 30) {
            return cell
        }
        return app.buttons.matching(predicate).firstMatch
    }

    /// Linha da biblioteca com o material de exemplo.
    private func libraryRow(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", "Anotações de estudo")
        let cell = app.cells.matching(predicate).firstMatch
        if cell.waitForExistence(timeout: 30) {
            return cell
        }
        let text = app.staticTexts.matching(predicate).firstMatch
        if text.waitForExistence(timeout: 5) {
            return text
        }
        return app.buttons.matching(predicate).firstMatch
    }

    /// Argumento de lançamento com os dados de exemplo (igual ao DemoSeed).
    private var launchArgument: String { "-uiTestSeed" }
}
