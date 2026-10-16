//
//  DiscursoBiblicoUITests.swift
//  DiscursoBiblicoUITests
//
//  Testes de interface no simulador (CI): navegam pelo aplicativo de verdade e
//  guardam capturas de tela como anexos do resultado; o workflow extrai e
//  publica essas imagens no artefato "capturas-simulador". É assim que o
//  aplicativo é conferido visualmente sem depender de um Mac.
//
//  O conteúdo de exemplo é criado pelo próprio aplicativo quando iniciado com
//  o argumento "-uiTestSeed" (ver DemoSeed.swift): um discurso com marcações,
//  referências, notas e indicações, além de um material indexado na
//  biblioteca. Sem o argumento, nada disso é criado.
//
//  Quatro cuidados que vieram de execuções reais no CI:
//
//  1. **Toque que "não chega".** No iOS 26 o `tap()` de um elemento tocável
//     às vezes não produz efeito: o XCUITest sintetiza o evento no lugar certo
//     e o aplicativo não reage (defeito conhecido das listas novas do SwiftUI
//     com o XCUITest; o mesmo vale para as abas). Por isso todo toque
//     importante passa por `tap(_:in:until:named:)`, que tenta pelo elemento,
//     depois por coordenada e depois com pressão curta, parando assim que a
//     tela esperada aparece — e registra no log qual tentativa funcionou.
//  2. **A versão do Xcode acompanha o simulador.** O simulador instalado no
//     runner é o iOS 26; testar com o Xcode 16.4 (SDK iOS 18) foi o que
//     produziu os toques sem efeito na primeira rodada. O workflow seleciona
//     o Xcode 26.x disponível.
//  3. **Nada de adivinhar o tipo do elemento.** A mesma linha de uma `List`
//     aparece como `button`, `cell` ou `staticText`; a busca olha os botões
//     primeiro (as linhas com acessibilidade combinada aparecem assim) e usa
//     `cells`/`staticTexts` como último recurso.
//  4. **Cada passo guarda a árvore de acessibilidade** junto da captura de
//     tela — e uma falha guarda também `falha-<passo>`. Quando algo falha, o
//     artefato do CI diz o que havia na tela, sem precisar de um Mac.
//

import XCTest

final class DiscursoBiblicoUITests: XCTestCase {

    /// Espera longa: o simulador do CI é bem mais lento que o de uma máquina
    /// de desenvolvimento.
    private let longa: TimeInterval = 60

    /// Espera curta (elementos já vistos, entre tentativas de toque).
    private let curta: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Discursos: lista, detalhe, editor e proferimento

    @MainActor
    func testDiscursoDetalheEditorEProferimento() throws {
        let app = launchSeededApp()

        // 1. Lista de discursos ("Continuar" e o discurso de exemplo).
        let row = speechRow(in: app)
        XCTAssertTrue(
            row.waitForExistence(timeout: longa),
            "O discurso de exemplo não apareceu na lista de discursos."
        )
        capture(app, named: "01-lista-de-discursos")

        // 2. Detalhe do discurso.
        let present = app.buttons["Abrir no modo de proferimento"]
        let edit = app.buttons["Editar discurso"]
        XCTAssertTrue(
            tap(row, in: app, until: { present.exists && edit.exists }, named: "abrir o discurso"),
            "A tela de detalhe do discurso não abriu."
        )
        capture(app, named: "02-detalhe-do-discurso")

        // 3. Editor.
        let editorDone = app.buttons["Pronto"]
        XCTAssertTrue(
            tap(edit, in: app, until: { editorDone.exists }, named: "abrir o editor"),
            "O editor do discurso não abriu."
        )
        capture(app, named: "03-editor-do-discurso")
        XCTAssertTrue(
            tap(editorDone, in: app, until: { !editorDone.exists && present.exists }, named: "fechar o editor"),
            "O editor não fechou."
        )

        // 4. Modo de proferimento.
        let textView = app.textViews.firstMatch
        XCTAssertTrue(
            tap(present, in: app, until: { textView.exists }, named: "abrir o proferimento"),
            "O modo de proferimento não abriu."
        )
        XCTAssertTrue(
            textView.waitForExistence(timeout: longa),
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
        let settings = app.buttons["Ajustes da apresentação"]
        XCTAssertTrue(
            tapPoint(in: app, until: { settings.exists }, named: "mostrar os controles"),
            "Os controles da apresentação não apareceram com um toque na tela."
        )
        capture(app, named: "05-proferimento-com-controles")

        // 6. Ajustes da apresentação (texto, tema, espaçamento).
        let settingsDone = app.buttons["Pronto"]
        XCTAssertTrue(
            tap(settings, in: app, until: { settingsDone.exists }, named: "abrir os ajustes"),
            "Os ajustes da apresentação não abriram."
        )
        capture(app, named: "06-ajustes-da-apresentacao")
        XCTAssertTrue(
            tap(settingsDone, in: app, until: { !settingsDone.exists && settings.exists }, named: "fechar os ajustes"),
            "Os ajustes da apresentação não fecharam."
        )

        // 7. Texto maior.
        let bigger = app.buttons["Aumentar o texto"]
        XCTAssertTrue(
            tap(bigger, in: app, until: { bigger.exists && settings.exists }, named: "aumentar o texto"),
            "O controle \"Aumentar o texto\" não apareceu."
        )
        tap(bigger, in: app, until: { bigger.exists && settings.exists }, named: "aumentar o texto de novo")
        capture(app, named: "07-proferimento-texto-maior")

        // 8. Próximo tópico (o indicador passa de "Tópico 1 de …" para "2").
        let topicTwo = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Tópico 2 ")
        ).firstMatch
        let nextTopic = app.buttons["Próximo tópico"]
        XCTAssertTrue(
            tap(nextTopic, in: app, until: { topicTwo.exists }, named: "próximo tópico"),
            "O controle \"Próximo tópico\" não apareceu ou não avançou o discurso."
        )
        capture(app, named: "08-proximo-topico")
    }

    // MARK: - Biblioteca, leitura e demais abas

    @MainActor
    func testBibliotecaLeituraEPesquisa() throws {
        let app = launchSeededApp()

        // 1. Biblioteca com o material de exemplo.
        openTab("Biblioteca", in: app)
        let item = findRow(containing: "Anotações de estudo", in: app)
        XCTAssertTrue(
            item.waitForExistence(timeout: longa),
            "O material de exemplo não apareceu na biblioteca."
        )
        capture(app, named: "09-biblioteca")

        // 2. Leitura interna do material (texto extraído e indexado).
        let readerBack = app.navigationBars.buttons["Biblioteca"]
        let readerSummary = app.buttons["Sumário"]
        XCTAssertTrue(
            tap(item, in: app, until: { readerSummary.exists || readerBack.exists }, named: "abrir o material"),
            "O leitor do material não abriu."
        )
        XCTAssertTrue(
            waitUntil(longa, { readerSummary.exists || readerBack.exists }),
            "O leitor do material não apareceu."
        )
        // A extração do texto pode levar alguns segundos na primeira vez.
        _ = waitUntil(curta, { app.staticTexts["Anotações de estudo (exemplo)"].exists })
        capture(app, named: "10-leitura-do-material")

        // 3. Volta para a biblioteca e mostra as demais abas.
        XCTAssertTrue(
            tap(readerBack, in: app, until: { !readerBack.exists }, named: "voltar para a biblioteca"),
            "O botão de voltar não apareceu no leitor (ou não voltou para a biblioteca)."
        )
        openTab("Pesquisar", in: app)
        XCTAssertTrue(
            app.navigationBars.staticTexts["Pesquisar"].waitForExistence(timeout: longa),
            "A aba Pesquisar não abriu."
        )
        capture(app, named: "11-pesquisar")

        openTab("Ajustes", in: app)
        XCTAssertTrue(
            app.navigationBars.staticTexts["Ajustes"].waitForExistence(timeout: longa),
            "A aba Ajustes não abriu."
        )
        capture(app, named: "12-ajustes")
    }

    // MARK: - Toques

    /// Toca no elemento até `until` ficar verdadeira, tentando três formas.
    ///
    /// No iOS 26 há toques sintetizados que não chegam ao aplicativo (o evento
    /// é registrado e nada acontece na tela). A ordem é: toque normal; toque
    /// real por coordenada (o conserto clássico desse defeito); toque com uma
    /// pressão curta (mais próximo de um toque humano lento). Cada tentativa
    /// só acontece depois de conferir que o alvo ainda é o que se espera, e o
    /// log registra qual funcionou.
    @discardableResult
    private func tap(
        _ element: XCUIElement,
        in app: XCUIApplication,
        until desired: () -> Bool,
        named step: String
    ) -> Bool {
        XCTAssertTrue(
            element.waitForExistence(timeout: longa),
            "\(step): o elemento não apareceu na tela."
        )
        if desired() { return true }

        let attempts: [(String, () -> Void)] = [
            ("elemento", { element.tap() }),
            ("coordenada", {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }),
            ("pressão curta", { element.press(forDuration: 0.12) }),
            ("coordenada", {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            })
        ]

        for (name, touch) in attempts {
            touch()
            if waitUntil(8, desired) {
                print("[ci] \(step): funcionou com o toque por \(name).")
                return true
            }
        }

        capture(app, named: "falha-\(step)")
        print("[ci] \(step): nenhuma das tentativas de toque teve efeito.")
        return false
    }

    /// Toca num ponto do meio da tela (usado para revelar os controles do
    /// modo de proferimento, que não têm botão de abrir).
    @discardableResult
    private func tapPoint(
        in app: XCUIApplication,
        until desired: () -> Bool,
        named step: String
    ) -> Bool {
        if desired() { return true }
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for attempt in 1...3 {
            middle.tap()
            if waitUntil(8, desired) {
                print("[ci] \(step): funcionou na tentativa \(attempt).")
                return true
            }
        }
        capture(app, named: "falha-\(step)")
        return false
    }

    /// Abre uma aba da barra inferior conferindo que ela ficou selecionada.
    private func openTab(_ name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(
            tap(tab, in: app, until: { tab.isSelected }, named: "aba \(name)"),
            "A aba \(name) não abriu."
        )
    }

    // MARK: - Consultas

    /// Espera até `until` ficar verdadeira (ou o tempo acabar).
    @discardableResult
    private func waitUntil(_ timeout: TimeInterval, _ until: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if until() { return true }
            // Um quadro para a interface responder (lista carregando etc.).
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return until()
    }

    /// A linha do discurso de exemplo (sem a linha "Continuar: …", que abre
    /// direto o modo de proferimento).
    private func speechRow(in app: XCUIApplication) -> XCUIElement {
        findRow(containing: "Discurso de exemplo", excluding: "Continuar:", in: app)
    }

    /// Procura um elemento tocável cujo rótulo contenha `text`.
    ///
    /// As linhas de `List` com acessibilidade combinada aparecem como botões;
    /// `cells` e `staticTexts` ficam como último recurso, porque variam com a
    /// versão do iOS. `excluding` descarta a linha "Continuar: …".
    private func findRow(
        containing text: String,
        excluding excluded: String? = nil,
        in app: XCUIApplication
    ) -> XCUIElement {
        var predicate = NSPredicate(format: "label CONTAINS %@", text)
        if let excluded {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                NSPredicate(format: "NOT (label CONTAINS %@)", excluded)
            ])
        }

        let button = app.buttons.matching(predicate).firstMatch
        if waitUntil(curta, { button.exists }) { return button }

        let cell = app.cells.matching(predicate).firstMatch
        if waitUntil(curta, { cell.exists }) { return cell }

        return app.staticTexts.matching(predicate).firstMatch
    }

    // MARK: - Apoio

    /// Abre o aplicativo com os dados de exemplo.
    ///
    /// O argumento é o mesmo de `DemoSeed.launchArgument` no aplicativo. O
    /// alvo de testes de interface não importa o módulo do app (ele dirige o
    /// app de fora, pela acessibilidade), então o valor é repetido aqui.
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
