//
//  PayloadCodingTests.swift
//  DiscursoBiblicoTests
//
//  Testes da codificação dos modelos do núcleo usada pelos registros do
//  SwiftData (e pelo backup).
//
//  O que precisa valer:
//   - ida e volta preserva todos os campos (inclusive aninhados);
//   - datas em ISO 8601 (o mesmo formato da implementação em arquivos), com
//     precisão de segundos — frações de segundo são normalizadas, como no
//     armazenamento em arquivo do núcleo;
//   - a codificação é estável/determinística (mesmos bytes para o mesmo valor);
//   - dados vazios ou inválidos nunca derrubam o aplicativo.
//
//  Por isso os dados de exemplo usam datas exatas (sem fração de segundo).
//

import DiscursoCore
import Foundation
import XCTest
@testable import DiscursoBiblico

final class PayloadCodingTests: XCTestCase {

    // MARK: Discursos

    func testDiscursoVaiEVoltaIdêntico() {
        let speech = AppSpeechFactory.makeSpeech()
        let data = PayloadCoding.encode(speech)
        XCTAssertFalse(data.isEmpty)

        let decoded = PayloadCoding.decode(Speech.self, from: data)
        XCTAssertEqual(decoded, speech)
    }

    func testPosiçãoDeLeituraEEstadoDaApresentaçãoSãoPreservados() {
        var speech = AppSpeechFactory.makeSpeech()
        speech.presentation = {
            var preferences = PresentationPreferences()
            preferences.fontSize = 52
            preferences.theme = .sepia
            preferences.autoScrollSpeed = 44
            preferences.showsPresenterNotes = true
            return preferences
        }()
        speech.lastReadPosition = ReadingPosition(
            sectionID: speech.sections.first?.id,
            blockID: speech.sections.first?.blocks.first?.id,
            scrollFraction: 0.42,
            offset: 512,
            sectionIndex: 0,
            updatedAt: AppSpeechFactory.referenceDate
        )

        let decoded = PayloadCoding.decode(Speech.self, from: PayloadCoding.encode(speech))
        XCTAssertEqual(decoded?.presentation, speech.presentation)
        XCTAssertEqual(decoded?.lastReadPosition, speech.lastReadPosition)
    }

    // MARK: Biblioteca

    func testMaterialDaBibliotecaVaiEVoltaIdêntico() {
        let itemID = UUID()
        let locator = ReadingLocator(kind: .chapterOffset, chapterIndex: 2, characterOffset: 120)
        var item = AppSpeechFactory.makeLibraryItem(id: itemID)
        item.notes = [
            LibraryNote(
                text: "Anotação pessoal",
                locator: locator,
                createdAt: AppSpeechFactory.referenceDate,
                updatedAt: AppSpeechFactory.referenceDate
            )
        ]
        item.bookmarks = [
            Bookmark(locator: locator, label: "Marcador", excerpt: "Trecho", createdAt: AppSpeechFactory.referenceDate)
        ]
        item.highlights = [
            Highlight(locator: locator, text: "Destaque", color: .yellow, note: "Importante", createdAt: AppSpeechFactory.referenceDate)
        ]
        item.lastReadPosition = LibraryReadingPosition(
            unitIndex: 3,
            fractionInsideUnit: 0.5,
            characterOffset: 120,
            updatedAt: AppSpeechFactory.referenceDate
        )
        item.indexStatus = .indexed
        item.unitCount = 12
        item.category = "Estudo"
        item.tags = ["referência"]
        item.isFavorite = true

        let decoded = PayloadCoding.decode(LibraryItem.self, from: PayloadCoding.encode(item))
        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded?.notes.first?.locator, locator)
        XCTAssertEqual(decoded?.highlights.first?.color, .yellow)
    }

    func testIndiceDeTextoVaiEVoltaIdêntico() {
        let index = LibraryTextIndex(
            itemID: UUID(),
            chunks: [
                LibraryTextChunk(locator: ReadingLocator(kind: .chapterOffset, chapterIndex: 0), title: "Capítulo 1", text: "Primeiro conteúdo."),
                LibraryTextChunk(locator: ReadingLocator(kind: .chapterOffset, chapterIndex: 1), title: "Capítulo 2", text: "Segundo conteúdo.")
            ],
            builtAt: AppSpeechFactory.referenceDate
        )
        let decoded = PayloadCoding.decode(LibraryTextIndex.self, from: PayloadCoding.encode(index))
        XCTAssertEqual(decoded, index)
        XCTAssertEqual(decoded?.totalWordCount, index.totalWordCount)
    }

    // MARK: Configurações

    func testConfiguraçõesEPerfilDeLeituraVãoEVoltam() {
        var settings = AppSettings.default
        settings.wordsPerMinute = 132
        settings.recentTags = ["fé", "esperança"]
        settings.defaultPresentation.fontSize = 46
        settings.lastOpenedSpeechID = UUID()

        let decodedSettings = PayloadCoding.decode(AppSettings.self, from: PayloadCoding.encode(settings))
        XCTAssertEqual(decodedSettings, settings)

        let profile = ReadingProfile(
            name: "Púlpito",
            preferences: settings.defaultPresentation,
            isBuiltIn: false,
            createdAt: AppSpeechFactory.referenceDate
        )
        let decodedProfile = PayloadCoding.decode(ReadingProfile.self, from: PayloadCoding.encode(profile))
        XCTAssertEqual(decodedProfile, profile)
    }

    // MARK: Pesquisa

    func testPesquisaSalvaHistóricoECacheVãoEVoltam() {
        let saved = AppSpeechFactory.makeSavedResearch()
        XCTAssertEqual(PayloadCoding.decode(SavedResearch.self, from: PayloadCoding.encode(saved)), saved)

        let entry = SearchHistoryEntry(
            query: "salmo 23",
            providerIDs: ["wol", "official-links"],
            resultCount: 7,
            searchedAt: AppSpeechFactory.referenceDate,
            failed: false
        )
        XCTAssertEqual(PayloadCoding.decode(SearchHistoryEntry.self, from: PayloadCoding.encode(entry)), entry)

        let cached = CachedResearchResults(
            query: "salmo 23",
            providerID: "wol",
            results: [saved.result],
            storedAt: AppSpeechFactory.referenceDate
        )
        XCTAssertEqual(PayloadCoding.decode(CachedResearchResults.self, from: PayloadCoding.encode(cached)), cached)
    }

    // MARK: Formato

    func testDatasSãoGravadasEmISO8601() {
        let speech = AppSpeechFactory.makeSpeech()
        let text = String(data: PayloadCoding.encode(speech), encoding: .utf8) ?? ""
        XCTAssertTrue(
            text.contains("2023-11-14T22:13:20Z"),
            "A data de criação deveria aparecer em ISO 8601; payload: \(text.prefix(400))"
        )
    }

    func testCodificaçãoÉDeterminística() {
        let speech = AppSpeechFactory.makeSpeech()
        XCTAssertEqual(PayloadCoding.encode(speech), PayloadCoding.encode(speech))
    }

    func testDadosVaziosOuInválidosNãoDerrubamODecodificador() {
        XCTAssertNil(PayloadCoding.decode(Speech.self, from: Data()))
        XCTAssertNil(PayloadCoding.decode(Speech.self, from: Data("não é json".utf8)))
        XCTAssertNil(PayloadCoding.decode(Speech.self, from: Data("{}".utf8)), "Objeto vazio não é um discurso válido")
    }
}
