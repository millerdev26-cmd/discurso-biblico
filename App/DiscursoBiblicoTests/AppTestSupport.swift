//
//  AppTestSupport.swift
//  DiscursoBiblicoTests
//
//  Auxiliares comuns dos testes da camada de aplicativo.
//
//  IMPORTANTE: este arquivo só usa Foundation + DiscursoCore e, por isso,
//  também é compilado/executado em Linux pelo script
//  `Scripts/verify_app_logic.sh`, que roda de verdade a parte da lógica do
//  app que não depende de SwiftUI/SwiftData/PDFKit.
//
//  Os testes que dependem de estruturas da Apple (SwiftData, PDFKit, UIKit)
//  ficam em arquivos com `#if canImport(...)` e são ignorados nessa
//  verificação.
//

import DiscursoCore
import Foundation

// MARK: - Arquivos temporários

/// Criação e limpeza de diretórios temporários para os testes.
enum AppTestSupport {

    /// Cria um diretório temporário exclusivo do teste.
    static func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscursoBiblicoTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Escreve um arquivo de texto no diretório informado.
    @discardableResult
    static func writeFile(named name: String, contents: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Escreve bytes no diretório informado.
    @discardableResult
    static func writeFile(named name: String, data: Data, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Dados de exemplo

/// Modelos de exemplo usados pelos testes do aplicativo.
///
/// (Os testes do `DiscursoCore` têm o próprio construtor; a camada de app
/// repete um conjunto pequeno para não depender dos internos do pacote.)
enum AppSpeechFactory {

    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Discurso com todos os tipos de bloco relevantes para a apresentação.
    static func makeSpeech(
        id: UUID = UUID(),
        title: String = "A oração que Deus ouve",
        now: Date = referenceDate
    ) -> Speech {
        var speech = Speech(
            id: id,
            title: title,
            subtitle: "Estudo para a reunião",
            occasion: "Reunião de meio de semana",
            tags: ["oração", "estudo"],
            createdAt: now,
            updatedAt: now,
            plannedMinutes: 30
        )

        var introduction = SpeechSection(title: "Introdução", subtitle: "Abertura")
        introduction.blocks = [
            SpeechBlock(kind: .heading, text: "Introdução"),
            SpeechBlock(kind: .paragraph, text: "Boa noite a todos. Vamos ler *João 3:16* e refletir {pausa: 2} sobre isso."),
            SpeechBlock(kind: .cue, cue: .pause, cueDetail: "2 segundos"),
            SpeechBlock(kind: .note, text: "Observar o tempo", isPresenterNote: true)
        ]

        var development = SpeechSection(title: "Desenvolvimento")
        development.blocks = [
            SpeechBlock(kind: .heading, text: "Desenvolvimento"),
            SpeechBlock(kind: .scripture, text: "Porque Deus amou o mundo", reference: BibleReference(bookID: .john, chapter: 3, verseStart: 16)),
            SpeechBlock(kind: .bulletList, items: ["Primeiro ponto", "Segundo ponto"]),
            SpeechBlock(kind: .quote, text: "Citação curta para reflexão.", isHighlighted: true)
        ]

        speech.sections = [introduction, development]
        speech.privateNotes = "Nota privada do pregador."
        speech.sources = [
            SourceLink(
                title: "A Sentinela — janeiro",
                url: URL(string: "https://wol.jw.org/pt/wol/d/r5/lp-t/2026001"),
                kind: .onlinePublication,
                publication: "A Sentinela",
                accessedAt: referenceDate
            )
        ]
        return speech
    }

    /// Material de biblioteca “de mentira”, sem arquivo associado.
    static func makeLibraryItem(
        id: UUID = UUID(),
        title: String = "Manual de estudo",
        now: Date = referenceDate
    ) -> LibraryItem {
        LibraryItem(
            id: id,
            title: title,
            author: "Autor de exemplo",
            kind: .plainText,
            fileName: "\(id.uuidString).txt",
            fileExtension: "txt",
            fileSize: 128,
            contentHash: "fnv1a64:0000000000000000",
            importedAt: now,
            indexStatus: .pending
        )
    }

    /// Fonte de pesquisa salva.
    static func makeSavedResearch(now: Date = referenceDate) -> SavedResearch {
        SavedResearch(
            query: "amor de Deus",
            result: ResearchResultPayload(
                providerID: "wol",
                title: "O amor de Deus",
                publication: "A Sentinela",
                snippet: "Trecho de exemplo.",
                urlString: "https://wol.jw.org/pt/wol/d/r5/lp-t/2026001",
                kind: .publication,
                accessedAt: now
            ),
            savedAt: now
        )
    }
}
