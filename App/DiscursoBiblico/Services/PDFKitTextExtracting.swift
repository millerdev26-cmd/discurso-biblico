//
//  PDFKitTextExtracting.swift
//  DiscursoBiblico
//
//  Extração de texto de PDF com o PDFKit (macOS/iOS).
//
//  Esta é a implementação "de verdade" prometida pelo protocolo
//  `PDFTextExtracting` do `DiscursoCore`: interpreta fontes, codificações e
//  páginas corretamente. O extrator puro em Swift do pacote continua sendo o
//  fallback usado nos testes em Linux.
//

import DiscursoCore
import Foundation
import PDFKit

struct PDFKitTextExtracting: PDFTextExtracting {

    /// Extrai o texto página a página. Nunca lança: devolve avisos na
    /// estrutura `PDFExtraction` (a indexação decide o que fazer).
    func extractText(from data: Data) -> PDFExtraction {
        guard let document = PDFDocument(data: data) else {
            return PDFExtraction(pages: [], isEncrypted: false, warnings: ["O PDF não pôde ser aberto."])
        }

        if document.isEncrypted && document.isLocked {
            // Protegido por senha: nada é lido e nada é contornado.
            return PDFExtraction(
                pages: [],
                isEncrypted: true,
                warnings: ["O PDF está protegido por senha."]
            )
        }

        var pages: [String] = []
        var warnings: [String] = []
        let pageCount = document.pageCount
        for index in 0..<pageCount {
            if let page = document.page(at: index), let text = page.string, !text.isEmpty {
                pages.append(text)
            } else {
                pages.append("")
                warnings.append("Página \(index + 1) sem texto extraível (pode ser digitalizada).")
            }
        }

        if pages.allSatisfy({ $0.isEmpty }), pageCount > 0 {
            warnings.append("Nenhum texto pôde ser extraído: o PDF parece ser digitalizado (imagens).")
        }

        return PDFExtraction(
            pages: pages,
            isEncrypted: document.isEncrypted,
            warnings: warnings
        )
    }
}
