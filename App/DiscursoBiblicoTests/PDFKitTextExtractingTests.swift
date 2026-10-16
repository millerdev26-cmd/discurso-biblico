//
//  PDFKitTextExtractingTests.swift
//  DiscursoBiblicoTests
//
//  Testes do extrator de PDF com PDFKit (a implementação "de verdade"
//  prometida pelo protocolo `PDFTextExtracting` do `DiscursoCore`).
//
//  Os PDFs de teste são gerados na hora com o `UIGraphicsPDFRenderer`.
//
//  Observação: a construção de um PDF protegido por senha não é feita aqui
//  (o `UIGraphicsPDFRenderer` não criptografa); esse caso é coberto com um
//  extrator controlado nos testes de importação e na verificação manual
//  descrita em `App/README.md`.
//
//  Este arquivo exige PDFKit/UIKit (iOS/macOS) e é ignorado na verificação
//  em Linux.
//

#if canImport(PDFKit) && canImport(UIKit)
import DiscursoCore
import Foundation
import PDFKit
import UIKit
import XCTest
@testable import DiscursoBiblico

final class PDFKitTextExtractingTests: XCTestCase {

    /// Gera um PDF com uma página por texto informado.
    /// Página com texto vazio fica em branco (simula digitalização).
    private func makePDF(pages: [String]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 560))
        return renderer.pdfData { context in
            for text in pages {
                context.beginPage()
                guard !text.isEmpty else { continue }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20),
                    .foregroundColor: UIColor.black
                ]
                (text as NSString).draw(at: CGPoint(x: 32, y: 40), withAttributes: attributes)
            }
        }
    }

    // MARK: Extração

    func testExtraiTextoPáginaAPágina() {
        let data = makePDF(pages: ["Primeira página do esboço.", "Segunda página do esboço."])

        let extraction = PDFKitTextExtracting().extractText(from: data)

        XCTAssertEqual(extraction.pages.count, 2)
        XCTAssertTrue(extraction.pages[0].contains("Primeira página"))
        XCTAssertTrue(extraction.pages[1].contains("Segunda página"))
        XCTAssertFalse(extraction.isEncrypted)
        XCTAssertTrue(extraction.warnings.isEmpty, "Avisos inesperados: \(extraction.warnings)")
    }

    func testExtraçãoAlimentaAIndexaçãoDoNúcleo() throws {
        let data = makePDF(pages: ["Conteúdo pesquisável desta página."])

        let result = try LibraryIndexer.buildIndex(
            itemID: UUID(),
            kind: .pdf,
            fileExtension: "pdf",
            data: data,
            pdfTextExtracting: PDFKitTextExtracting()
        )

        XCTAssertEqual(result.unitCount, 1)
        XCTAssertEqual(result.index.chunks.first?.title, "Página 1")
        XCTAssertTrue(result.index.fullText.contains("Conteúdo pesquisável"))
    }

    // MARK: Casos de problema

    func testArquivoInválidoGeraAvisoSemQuebrar() {
        let extraction = PDFKitTextExtracting().extractText(from: Data("isto não é um PDF".utf8))

        XCTAssertTrue(extraction.pages.isEmpty)
        XCTAssertFalse(extraction.isEncrypted)
        XCTAssertEqual(extraction.warnings, ["O PDF não pôde ser aberto."])
    }

    func testPáginaEmBrancoÉSinalizada() {
        let data = makePDF(pages: ["", "Com texto na segunda página."])

        let extraction = PDFKitTextExtracting().extractText(from: data)

        XCTAssertEqual(extraction.pages.count, 2)
        XCTAssertTrue(extraction.pages[1].contains("Com texto na segunda página"))
        if extraction.pages[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            XCTAssertTrue(
                extraction.warnings.contains { $0.contains("Página 1") },
                "Página sem texto deveria aparecer nos avisos: \(extraction.warnings)"
            )
        }
    }

    func testPDFTodoEmBrancoÉDetectadoComoDigitalizado() {
        let data = makePDF(pages: ["", ""])

        let extraction = PDFKitTextExtracting().extractText(from: data)

        XCTAssertEqual(extraction.pages.count, 2)
        let empties = extraction.pages.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if empties {
            XCTAssertTrue(
                extraction.warnings.contains { $0.contains("digitalizado") },
                "Um PDF sem nenhum texto deveria ser sinalizado como digitalizado: \(extraction.warnings)"
            )
        }
    }
}
#endif
