//
//  DemoSeed.swift
//  DiscursoBiblico
//
//  Conteúdo de exemplo usado apenas pelos testes de interface (CI).
//
//  O modo é ligado pelo argumento de lançamento "-uiTestSeed". Sem esse
//  argumento nada aqui roda: no uso normal o aplicativo nunca cria conteúdo
//  sozinho — nem discursos, nem materiais de biblioteca.
//
//  Os dados existem para que as capturas de tela feitas na nuvem mostrem
//  telas com conteúdo de verdade: marcações de orador, referências bíblicas,
//  notas do apresentador e um material de leitura indexado para a busca
//  offline. Como em todo o aplicativo, nenhum texto bíblico é copiado:
//  apenas as referências.
//

import DiscursoCore
import Foundation

enum DemoSeed {

    /// Argumento de lançamento que liga os dados de exemplo.
    static let launchArgument = "-uiTestSeed"

    /// `true` quando o processo foi iniciado com o argumento.
    static var isRequested: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    // MARK: - Instalação

    /// Cria o conteúdo de exemplo, uma única vez, apenas em banco vazio.
    @MainActor
    static func install(into environment: AppEnvironment) async {
        let speeches = (try? await environment.speechRepository.loadSummaries()) ?? []
        if speeches.isEmpty {
            try? await environment.speechRepository.save(makeSpeech())
        }

        let items = (try? await environment.libraryRepository.loadItems()) ?? []
        if items.isEmpty {
            await installLibraryItem(into: environment)
        }
    }

    /// Importa o material de exemplo pela mesma via usada pelo usuário
    /// (triagem, armazenamento e indexação), para exercitar o caminho real.
    private static func installLibraryItem(into environment: AppEnvironment) async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscursoBiblico-Exemplo", isDirectory: true)
        let fileURL = directory.appendingPathComponent("Anotações de estudo (exemplo).md")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        _ = await environment.importer.importFiles(at: [fileURL])
    }

    // MARK: - Discurso de exemplo

    /// Discurso com marcações, referências, notas e indicações de orador.
    static func makeSpeech(now: Date = Date()) -> Speech {
        Speech(
            title: "Discurso de exemplo — João 3:16",
            subtitle: "Criado pelos testes de interface para as capturas de tela",
            occasion: "Reunião de fim de semana",
            tags: ["exemplo", "esperança"],
            createdAt: now,
            updatedAt: now,
            plannedMinutes: 30,
            sections: [introduction, development, application, conclusion],
            status: .preparing,
            isFavorite: true
        )
    }

    private static var introduction: SpeechSection {
        SpeechSection(
            title: "Introdução",
            plannedMinutes: 5,
            blocks: [
                .cue(.pause, detail: "espere a assistência se acomodar"),
                .paragraph("Boa noite a todos. A consideração de hoje parte de um texto muito conhecido: João 3:16."),
                .paragraph("Vamos ver por que essa passagem é chamada de *resumo da esperança* e como ela pode influenciar decisões simples do dia a dia."),
                .note("Falar um pouco mais devagar na primeira frase e conferir o som da sala.")
            ]
        )
    }

    private static var development: SpeechSection {
        SpeechSection(
            title: "Desenvolvimento 1 — a base da esperança",
            plannedMinutes: 10,
            blocks: [
                .heading("A base da esperança"),
                .paragraph("A esperança apresentada na Bíblia não depende das circunstâncias. Ela se apoia em promessas registradas nas Escrituras, como Salmo 23:1-4 e Romanos 15:13."),
                .bullets([
                    "Quem faz a promessa?",
                    "Que garantia existe de que ela se cumprirá?",
                    "Como isso consola quem está desanimado?"
                ]),
                SpeechBlock(
                    kind: .quote,
                    text: "A esperança é a âncora que mantém a fé firme mesmo em meio à dificuldade."
                ),
                .note("Depois da citação, fazer uma pausa de dois segundos {pausa: 2} e deixar a ideia assentar.")
            ]
        )
    }

    private static var application: SpeechSection {
        SpeechSection(
            title: "Desenvolvimento 2 — como isso alcança o ouvinte",
            plannedMinutes: 9,
            blocks: [
                .heading("Como isso alcança o ouvinte"),
                .paragraph("Se Deus se importa com cada pessoa, isso precisa aparecer em atitudes concretas: *paciência* em casa, *gentileza* no trabalho e perdão quando algo machuca (Colossenses 3:13)."),
                .cue(.toneChange, detail: "tom mais caloroso"),
                .paragraph("Talvez alguém pense: “Isso soa bonito, mas minha rotina não deixa espaço.” É justamente aí que a esperança entra: pequenas decisões fiéis, todos os dias."),
                .paragraph("O convite não é para uma vida sem problemas, mas para uma vida com propósito. {olhar} Olhe para a assistência e fale a última frase com convicção.")
            ]
        )
    }

    private static var conclusion: SpeechSection {
        SpeechSection(
            title: "Conclusão",
            plannedMinutes: 6,
            blocks: [
                .heading("Conclusão"),
                .paragraph("Voltemos ao texto inicial: João 3:16. O convite é simples: conhecer melhor quem fez essa promessa e vivê-la com confiança."),
                .cue(.emphasis),
                .paragraph("Que cada um de nós encontre nessa esperança a força para o dia de hoje e para o que vem."),
                .note("Encerrar com um convite para conversar mais; anotar quem demonstrou interesse.")
            ]
        )
    }

    // MARK: - Material de biblioteca

    /// Markdown de exemplo (com títulos, listas e referências).
    static let markdown = """
    # Anotações de estudo (exemplo)

    Este material de exemplo é criado pelos testes de interface. Ele fica na
    biblioteca, pode ser lido dentro do aplicativo e aparece na busca offline.

    ## Esperança que se apoia em promessas

    - João 3:16 — amor que age em favor das pessoas.
    - Salmo 23:1-4 — cuidado e orientação.
    - Romanos 15:13 — alegria e paz na esperança.

    ## Como usar estas anotações

    1. Abra o material na Biblioteca.
    2. Toque em uma referência para consultar a fonte oficial.
    3. Use a aba Pesquisar para encontrar este texto mesmo sem internet.

    ## Lembrete para o orador

    Preparação não é só escrever: é treinar a leitura em voz alta, marcar as
    pausas e voltar ao ponto de leitura na próxima vez.
    """
}
