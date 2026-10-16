//
//  DemoSeed+Environment.swift
//  DiscursoBiblico
//
//  Instalação do conteúdo de exemplo no armazenamento real do aplicativo.
//
//  Fica separada de DemoSeed.swift (que é Swift puro) porque conversa com o
//  AppEnvironment — e, portanto, com SwiftData. Assim o conteúdo semeado, que
//  é o que os testes de interface precisam encontrar na tela, continua
//  verificável em Linux pelo Scripts/verify_app_logic.sh.
//
//

import DiscursoCore
import Foundation

extension DemoSeed {

    /// Cria o conteúdo de exemplo, uma única vez, apenas em banco vazio.
    ///
    /// Sem o argumento de lançamento nada disso roda: um usuário normal nunca
    /// vê conteúdo criado pelo aplicativo.
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
}