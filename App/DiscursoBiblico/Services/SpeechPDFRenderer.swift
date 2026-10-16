//
//  SpeechPDFRenderer.swift
//  DiscursoBiblico
//
//  Exportação em PDF.
//
//  O núcleo monta o HTML do discurso (`SpeechExporter.pdfRequest`); aqui o
//  UIKit transforma esse HTML em PDF, página a página, com o renderizador de
//  impressão do sistema. Nenhuma dependência externa.
//
//  Limitação honesta: o renderizador de impressão do iOS não é um navegador
//  completo. O HTML produzido pelo núcleo usa apenas títulos, parágrafos,
//  listas, negrito/itálico e citações — tudo com suporte garantido.
//

import DiscursoCore
import Foundation
import UIKit

@MainActor
enum SpeechPDFRenderer {

    /// Tamanho A4 a 72 pontos/polegada (padrão do PDF).
    static let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    static let margin: CGFloat = 48

    static func render(_ request: SpeechPDFRequest) -> Data {
        let formatter = UIMarkupTextPrintFormatter(markupText: request.html)
        formatter.perPageContentInsets = UIEdgeInsets(
            top: margin,
            left: margin,
            bottom: margin,
            right: margin
        )

        let renderer = FixedPagePrintRenderer(pageRect: pageRect, margin: margin)
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, pageRect, [
            kCGPDFContextTitle as String: request.title
        ])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        let bounds = UIGraphicsGetPDFContextBounds()
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: bounds)
        }
        UIGraphicsEndPDFContext()

        return data as Data
    }

    /// Grava o PDF em um arquivo temporário, pronto para o Compartilhar.
    static func renderToTemporaryFile(_ request: SpeechPDFRequest) throws -> URL {
        let data = render(request)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscursoBiblico", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(request.suggestedFileName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

/// Renderizador com papel fixo (A4) — o `UIPrintPageRenderer` padrão só
/// conhece o papel na hora de imprimir.
private final class FixedPagePrintRenderer: UIPrintPageRenderer {

    private let fixedPaperRect: CGRect
    private let fixedPrintableRect: CGRect

    init(pageRect: CGRect, margin: CGFloat) {
        self.fixedPaperRect = pageRect
        self.fixedPrintableRect = pageRect.insetBy(dx: margin, dy: margin)
        super.init()
    }

    override var paperRect: CGRect { fixedPaperRect }
    override var printableRect: CGRect { fixedPrintableRect }
}
