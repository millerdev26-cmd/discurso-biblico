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
//  Três cuidados que vieram de execuções reais no CI:
//
//  1. **Nada de depender do tipo de elemento.** Depending do iOS, a mesma
//     linha de uma `List` aparece como `cell`, `button` ou `staticText`. O
//     teste procura em todos os descendentes e aceita o primeiro elemento
//     realmente tocável (`hitPoint`), em vez de adivinhar o tipo.
//  2. **Cada passo guarda a árvore de acessibilidade** junto da captura de
//     tela. Quando algo falha, o anexo `.txt` diz o que havia na tela — sem
//     precisar de um Mac para descobrir.
//  3. **Esperas generosas e explícitas.** O simulador do CI é lento (cada
//     toque leva segundos); toda espera diz o que era esperado e por quanto
//     tempo.
//

import XCTest

final class DiscursoBiblicoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Tempo padrão de espera: o simulador do CI é bem mais lento que o de
    /// uma máquina de desenvolvimento.
    private let timeout: TimeInterval = 60

    // MARK: - Discursos: lista, detalhe, editor e proferimento

    @MainActor
    func testDiscursoDetalheEditorEProferimento() throws {
        let app = launchSeededApp()

        // 1. Lista de discursos ("Continuar" e o discurso de exemplo).
        let row = row(containing: "Discurso de exemplo", excluding: "Continuar:", in: app)
        XCTAssertNotNil(row, "O discurso de exemplo não apareceu na lista de discursos.")
        capture(app, named: "01-lista-de-discursos")
        row!.tap()

        // 2. Detalhe do discurso.
        let present = app.buttons["Abrir no modo de proferimento"]
        XCTAssertTrue(
            present.waitForExistence(timeout: timeout),
            "A tela de detalhe do discurso não abriu (esperado o botão \"Abrir no modo de proferimento\")."
        )
        capture(app, named: "02-detalhe-do-discurso")

        // 3. Editor.
        let edit = app.buttons["Editar discurso"]
        XCTAssertTrue(edit.waitForExistence(timeout: timeout), "O botão de editar não apareceu no detalhe.")
        edit.tap()
        let editorDone = app.buttons["Pronto"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: timeout), "O editor do discurso não abriu.")
        capture(app, named: "03-editor-do-discurso")
        editorDone.tap()

        // 4. Volta ao detalhe e abre o modo de proferimento.
        XCTAssertTrue(
            present.waitForExistence(timeout: timeout),
            "A tela de detalhe não voltou depois de fechar o editor."
        )
        present.tap()

        let textView = app.textViews.firstMatch
        XCTAssertTrue(
            textView.waitForExistence(timeout: timeout),
            "O modo de proferimento não abriu."
        )
        if let content = textView.value as? String {
            XCTAssertTrue(
                content.contains("Boa noite"),
                "O texto do discurso não apareceu na apresentação (início: \(content.prefix(120)))."
            )
        }
        capture(app, named: "04-proferimento")

        // 5. Um toque no meio da tela revela os controles.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let settings = app.buttons["Ajustes da apresentação"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: timeout),
            "Os controles da apresentação não apareceram com um toque na tela."
        )
        capture(app, named: "05-proferimento-com-controles")

        // 6. Ajustes da apresentação (texto, tema, espaçamento).
        settings.tap()
        let settingsDone = app.buttons["Pronto"]
        XCTAssertTrue(
            settingsDone.waitForExistence(timeout: timeout),
            "Os ajustes da apresentação não abriram."
        )
        capture(app, named: "06-ajustes-da-apresentacao")
        settingsDone.tap()

        // 7. Texto maior e salto para o próximo tópico.
        let bigger = app.buttons["Aumentar o texto"]
        XCTAssertTrue(bigger.waitForExistence(timeout: timeout), "O controle \"Aumentar o texto\" não apareceu.")
        bigger.tap()
        bigger.tap()
        capture(app, named: "07-proferimento-texto-maior")

        let nextTopic = app.buttons["Próximo tópico"]
        XCTAssertTrue(nextTopic.waitForExistence(timeout: timeout), "O controle \"Próximo tópico\" não apareceu.")
        nextTopic.tap()
        capture(app, named: "08-proximo-topico")
    }

    // MARK: - Biblioteca, leitura e demais abas

    @MainActor
    func testBibliotecaLeituraEPesquisa() throws {
        let app = launchSeededApp()

        // 1. Biblioteca com o material de exemplo.
        let biblioteca = app.tabBars.buttons["Biblioteca"]
        XCTAssertTrue(biblioteca.waitForExistence(timeout: timeout), "A aba Biblioteca não apareceu.")
        biblioteca.tap()

        let item = row(containing: "Anotações de estudo", in: app)
        XCTAssertNotNil(item, "O material de exemplo não apareceu na biblioteca.")
        capture(app, named: "09-biblioteca")
        item!.tap()

        // 2. Leitura interna do material (texto extraído e indexado).
        let readerTitle = app.navigationBars.staticTexts["Anotações de estudo (exemplo)"]
        XCTAssertTrue(
            readerTitle.waitForExistence(timeout: timeout),
            "O leitor do material não abriu (esperado o título \"Anotações de estudo (exemplo)\")."
        )
        capture(app, named: "10-leitura-do-material")

        // 3. Volta para a biblioteca e mostra as demais abas.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: timeout), "O botão de voltar não apareceu no leitor.")
        back.tap()

        let pesquisar = app.tabBars.buttons["Pesquisar"]
        XCTAssertTrue(
            pesquisar.waitForExistence(timeout: timeout),
            "A barra de abas não voltou depois de sair do leitor."
        )
        pesquisar.tap()
        XCTAssertTrue(
            app.navigationBars.staticTexts["Pesquisar"].waitForExistence(timeout: timeout),
            "A aba Pesquisar não abriu."
        )
        capture(app, named: "11-pesquisar")

        let ajustes = app.tabBars.buttons["Ajustes"]
        XCTAssertTrue(ajustes.waitForExistence(timeout: timeout), "A aba Ajustes não apareceu.")
        ajustes.tap()
        XCTAssertTrue(
            app.navigationBars.staticTexts["Ajustes"].waitForExistence(timeout: timeout),
            "A aba Ajustes não abriu."
        )
        capture(app, named: "12-ajustes")
    }

    // MARK: - Apoio

    /// Abre o aplicativo com os dados de exemplo.
    ///
    /// O argumento é o mesmo de `DemoSeed.launchArgument` no aplicativo. O
    /// alvo de testes de interface não importa o módulo do app (ele dirige o
    /// app de fora, por(accessibilidade)), então o valor é repetido aqui.
    private func launchSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        XCTAssertTrue(
            app.tabBars.buttons["Discursos"].waitForExistence(timeout: 120),
            "O aplicativo não abriu a tela principal."
        )
        return app
    }

    /// Procura um elemento tocável cujo rótulo contenha `text`.
    ///
    /// A mesma linha de uma lista aparece como `cell`, `button` ou
    /// `staticText` conforme o iOS; por isso a busca é feita em todos os
    /// descendentes, e só é aceito o primeiro elemento que pode receber o
    /// toque. `excluding` descarta a linha "Continuar: …", que leva o mesmo
    /// título mas abre direto o modo de proferimento.
    private func row(
        containing text: String,
        excluding excluded: String? = nil,
        in app: XCUIApplication
    ) -> XCUIElement? {
        var predicate = NSPredicate(format: "label CONTAINS %@", text)
        if let excluded {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                NSPredicate(format: "NOT (label CONTAINS %@)", excluded)
            ])
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let candidates = app.descendants(matching: .any).matching(predicate)
            for index in 0..<candidates.count {
                let candidate = candidates.element(boundBy: index)
                if candidate.exists, candidate.isHittable {
                    return candidate
                }
            }
            // Um quadro para a interface responder (lista carregando,etc.).
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        return nil
    }

    /// Guarda uma captura da tela e a árvore de acessibilidade como anexos.
    ///
    /// A captura é a evidência visual; o texto é o diagnóstico — sem ele, uma
    /// falha no CI só diz "não achou o botão", sem dizer o que havia na tela.
    private func capture(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-arvore"
        tree.lifetime = .keepAlways
        add(tree)
    }

    }