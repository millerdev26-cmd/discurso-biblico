//
//  PresentationTextBuilderTests.swift
//  DiscursoBiblicoTests
//
//  Testes da montagem do texto do modo de proferimento: títulos, faixas das
//  seções (usadas para medir e navegar), marcações, notas do apresentador,
//  ligações das referências e destaques.
//
//  Este arquivo exige UIKit (iOS/macOS) e é ignorado na verificação em Linux.
//

#if canImport(UIKit)
import DiscursoCore
import UIKit
import XCTest
@testable import DiscursoBiblico

final class PresentationTextBuilderTests: XCTestCase {

    private func build(_ speech: Speech, _ preferences: PresentationPreferences) -> PresentationTextBuilder.Result {
        PresentationTextBuilder(speech: speech, preferences: preferences).build()
    }

    // MARK: Estrutura

    func testFaixasDasSeçõesCobremOTextoCorrespondente() {
        let speech = AppSpeechFactory.makeSpeech()
        var preferences = PresentationPreferences()
        preferences.highlightsReferences = false

        let result = build(speech, preferences)
        XCTAssertEqual(result.sectionRanges.count, speech.sections.count)

        let full = result.attributedText.string as NSString
        let firstSection = full.substring(with: result.sectionRanges[0])
        XCTAssertTrue(firstSection.contains("Introdução"))
        XCTAssertTrue(firstSection.contains("Boa noite a todos"))

        let secondSection = full.substring(with: result.sectionRanges[1])
        XCTAssertTrue(secondSection.contains("Desenvolvimento"))
        XCTAssertTrue(secondSection.contains("Primeiro ponto"))
        XCTAssertFalse(secondSection.contains("Boa noite a todos"), "As seções não podem se sobrepor")
    }

    func testTítuloVazioUsaRótuloPadrão() {
        var speech = AppSpeechFactory.makeSpeech()
        speech.sections = [SpeechSection(title: "Tópico sem título")]
        speech.sections[0].blocks = [SpeechBlock(kind: .heading, text: "")]

        let result = build(speech, PresentationPreferences())
        XCTAssertTrue(result.attributedText.string.contains("Tópico"))
    }

    func testListaECitaçãoRecebemMarcaçãoLegível() {
        let speech = AppSpeechFactory.makeSpeech()
        var preferences = PresentationPreferences()
        preferences.highlightsReferences = false

        let text = build(speech, preferences).attributedText.string
        XCTAssertTrue(text.contains("•  Primeiro ponto"))
        XCTAssertTrue(text.contains("“Citação curta para reflexão.”"))
    }

    // MARK: Marcações em linha

    func testMarcaçõesEmLinhaSãoRemovidasNaApresentação() {
        let speech = AppSpeechFactory.makeSpeech()

        let text = build(speech, PresentationPreferences()).attributedText.string
        XCTAssertFalse(text.contains("*"), "A ênfase não deve aparecer com asteriscos: \(text)")
        XCTAssertFalse(text.contains("{pausa"), "As indicações em linha não devem aparecer cruas: \(text)")
        XCTAssertTrue(text.contains("Vamos ler João 3:16 e refletir sobre isso."))
    }

    func testIndicaçãoEmBlocoApareceComoOrientaçãoDiscreta() {
        let speech = AppSpeechFactory.makeSpeech()

        let text = build(speech, PresentationPreferences()).attributedText.string
        XCTAssertTrue(text.contains("[Pausa"), "A indicação de bloco orienta o orador: \(text)")
        XCTAssertTrue(text.contains("2 segundos"))
    }

    // MARK: Notas do apresentador

    func testNotasPrivadasSóAparecemQuandoSolicitado() {
        let speech = AppSpeechFactory.makeSpeech()

        var hidden = PresentationPreferences()
        hidden.showsPresenterNotes = false
        XCTAssertFalse(build(speech, hidden).attributedText.string.contains("Observar o tempo"))

        var shown = PresentationPreferences()
        shown.showsPresenterNotes = true
        XCTAssertTrue(build(speech, shown).attributedText.string.contains("Observar o tempo"))
    }

    // MARK: Referências

    func testReferênciasViraramLigaçõesInternasTocáveis() throws {
        let speech = AppSpeechFactory.makeSpeech()
        var preferences = PresentationPreferences()
        preferences.highlightsReferences = true

        let attributed = build(speech, preferences).attributedText
        let full = attributed.string as NSString
        let range = full.range(of: "João 3:16")
        XCTAssertNotEqual(range.location, NSNotFound, "O texto apresentado deveria conter a referência")

        let attributes = attributed.attributes(at: range.location, effectiveRange: nil)
        let link = try XCTUnwrap(attributes[.link] as? NSURL, "A referência deveria receber uma ligação")
        XCTAssertEqual(link.scheme, BibleReferenceLink.scheme)
        XCTAssertEqual(link.host, "43")
        XCTAssertEqual(link.path, "/3/16")
    }

    func testReferênciasNãoSãoDestacadasQuandoPreferênciaDesligada() {
        let speech = AppSpeechFactory.makeSpeech()
        var preferences = PresentationPreferences()
        preferences.highlightsReferences = false

        let attributed = build(speech, preferences).attributedText
        let full = attributed.string as NSString
        let range = full.range(of: "João 3:16")
        XCTAssertNotEqual(range.location, NSNotFound)

        let attributes = attributed.attributes(at: range.location, effectiveRange: nil)
        XCTAssertNil(attributes[.link], "Sem destaque, a referência continua sendo texto comum")
    }

    // MARK: Destaques e preferências tipográficas

    func testTrechoDestacadoRecebeCorDeFundo() {
        let speech = AppSpeechFactory.makeSpeech()
        var preferences = PresentationPreferences()
        preferences.highlightsReferences = false

        let attributed = build(speech, preferences).attributedText
        let full = attributed.string as NSString
        let range = full.range(of: "Citação curta")
        XCTAssertNotEqual(range.location, NSNotFound)

        let attributes = attributed.attributes(at: range.location, effectiveRange: nil)
        XCTAssertNotNil(attributes[.backgroundColor], "O trecho marcado como importante deveria ter fundo destacado")
    }

    func testPreferênciasTipográficasChegamAoParágrafo() {
        let speech = AppSpeechFactory.makeSpeech()
        var preferences = PresentationPreferences()
        preferences.lineHeightMultiple = 1.8
        preferences.alignment = .justified

        let attributed = build(speech, preferences).attributedText
        let full = attributed.string as NSString
        let range = full.range(of: "Boa noite")
        let attributes = attributed.attributes(at: range.location, effectiveRange: nil)

        let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(paragraph?.lineHeightMultiple ?? 0, 1.8, accuracy: 0.001)
        XCTAssertEqual(paragraph?.alignment, .justified)
    }

    func testTítulosSãoMaioresQueOParágrafo() {
        let speech = AppSpeechFactory.makeSpeech()
        var preferences = PresentationPreferences()
        preferences.highlightsReferences = false

        let attributed = build(speech, preferences).attributedText
        let full = attributed.string as NSString
        let headingRange = full.range(of: "Introdução")
        let paragraphRange = full.range(of: "Boa noite")

        let headingFont = attributed.attributes(at: headingRange.location, effectiveRange: nil)[.font] as? UIFont
        let paragraphFont = attributed.attributes(at: paragraphRange.location, effectiveRange: nil)[.font] as? UIFont

        XCTAssertNotNil(headingFont)
        XCTAssertNotNil(paragraphFont)
        XCTAssertGreaterThan(headingFont?.pointSize ?? 0, paragraphFont?.pointSize ?? 0)
    }

    // MARK: Tema

    func testTemaEscuroMudaAsCoresDoTexto() {
        let speech = AppSpeechFactory.makeSpeech()
        var light = PresentationPreferences()
        light.theme = .light
        var dark = PresentationPreferences()
        dark.theme = .dark

        let lightColor = build(speech, light).attributedText
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        let darkColor = build(speech, dark).attributedText
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor

        XCTAssertNotNil(lightColor)
        XCTAssertNotNil(darkColor)
        XCTAssertNotEqual(lightColor, darkColor)
    }
}
#endif
