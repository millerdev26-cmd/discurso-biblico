//
//  SpeechExporter.swift
//  DiscursoCore
//
//  Exportação de discursos em TXT, Markdown, HTML e PDF.
//
//  TXT, Markdown e HTML são gerados aqui mesmo (Swift puro). O PDF é gerado
//  no aplicativo iOS a partir do HTML (PDFKit/UIGraphicsPDFRenderer), porque
//  a renderização de páginas depende do UIKit; o pedido de renderização
//  (`SpeechPDFRequest`) leva tudo o que a camada do aplicativo precisa.
//

import Foundation

/// Formatos de exportação.
public enum SpeechExportFormat: String, Codable, CaseIterable, Sendable {
    case plainText
    case markdown
    case html
    case pdf

    public var displayName: String {
        switch self {
        case .plainText: return "Texto (.txt)"
        case .markdown: return "Markdown (.md)"
        case .html: return "Página da web (.html)"
        case .pdf: return "PDF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .html: return "html"
        case .pdf: return "pdf"
        }
    }

    public var mimeType: String {
        switch self {
        case .plainText: return "text/plain"
        case .markdown: return "text/markdown"
        case .html: return "text/html"
        case .pdf: return "application/pdf"
        }
    }

    public var systemImageName: String {
        switch self {
        case .plainText: return "doc.plaintext"
        case .markdown: return "text.alignleft"
        case .html: return "globe"
        case .pdf: return "doc.richtext"
        }
    }

    /// `true` quando o conteúdo precisa ser renderizado pela camada iOS.
    public var requiresPlatformRendering: Bool { self == .pdf }
}

/// Opções de exportação.
public struct SpeechExportOptions: Hashable, Sendable {
    /// Inclui notas do apresentador (notas privadas).
    public var includePresenterNotes: Bool
    /// Inclui as fontes associadas.
    public var includeSources: Bool
    /// Inclui o cabeçalho com ocasião, duração e etiquetas.
    public var includeMetadata: Bool

    public static let `default` = SpeechExportOptions()

    public init(
        includePresenterNotes: Bool = true,
        includeSources: Bool = true,
        includeMetadata: Bool = true
    ) {
        self.includePresenterNotes = includePresenterNotes
        self.includeSources = includeSources
        self.includeMetadata = includeMetadata
    }
}

/// Conteúdo pronto para ser gravado ou compartilhado.
public struct SpeechExportPayload: Sendable {
    public var format: SpeechExportFormat
    /// Nome de arquivo sugerido.
    public var suggestedFileName: String
    public var mimeType: String
    /// Conteúdo textual. Para `.pdf`, é o HTML que o aplicativo deve renderizar.
    public var content: String
    /// `true` quando `content` é HTML a ser convertido em PDF pelo aplicativo.
    public var needsPDFRendering: Bool
    /// Texto puro correspondente, para pré-visualização rápida.
    public var previewText: String

    public init(
        format: SpeechExportFormat,
        suggestedFileName: String,
        mimeType: String,
        content: String,
        needsPDFRendering: Bool,
        previewText: String
    ) {
        self.format = format
        self.suggestedFileName = suggestedFileName
        self.mimeType = mimeType
        self.content = content
        self.needsPDFRendering = needsPDFRendering
        self.previewText = previewText
    }
}

/// Erros de exportação.
public enum SpeechExportError: LocalizedError, Equatable {
    case emptySpeech
    case pdfRenderingUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptySpeech:
            return "Este discurso ainda não tem conteúdo para exportar."
        case .pdfRenderingUnavailable:
            return "A geração de PDF está disponível apenas no aplicativo (iOS)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .emptySpeech:
            return "Escreva pelo menos um tópico antes de exportar."
        case .pdfRenderingUnavailable:
            return "Exporte em Markdown ou HTML, ou gere o PDF pelo aplicativo."
        }
    }
}

/// Pedido de renderização de PDF para a camada do aplicativo (iOS).
public struct SpeechPDFRequest: Sendable {
    /// HTML autocontido, pronto para ser renderizado.
    public var html: String
    public var suggestedFileName: String
    /// Título usado no cabeçalho do documento.
    public var title: String

    public init(html: String, suggestedFileName: String, title: String) {
        self.html = html
        self.suggestedFileName = suggestedFileName
        self.title = title
    }
}

public enum SpeechExporter {

    /// Gera o conteúdo de exportação em um formato.
    public static func payload(
        for speech: Speech,
        format: SpeechExportFormat,
        options: SpeechExportOptions = .default
    ) throws -> SpeechExportPayload {
        guard !speech.sections.isEmpty || !speech.privateNotes.isEmpty else {
            throw SpeechExportError.emptySpeech
        }

        let fileName = SpeechTextRenderer.suggestedFileName(for: speech, extension: format.fileExtension)

        switch format {
        case .plainText:
            let content = text(
                of: speech,
                options: options,
                render: { SpeechTextRenderer.plainText(
                    of: $0,
                    includePresenterNotes: options.includePresenterNotes,
                    includeSources: options.includeSources
                ) }
            )
            return SpeechExportPayload(
                format: format,
                suggestedFileName: fileName,
                mimeType: format.mimeType,
                content: content,
                needsPDFRendering: false,
                previewText: content
            )
        case .markdown:
            let content = text(
                of: speech,
                options: options,
                render: { SpeechTextRenderer.markdown(
                    of: $0,
                    includePresenterNotes: options.includePresenterNotes,
                    includeSources: options.includeSources
                ) }
            )
            return SpeechExportPayload(
                format: format,
                suggestedFileName: fileName,
                mimeType: format.mimeType,
                content: content,
                needsPDFRendering: false,
                previewText: SpeechTextRenderer.plainText(
                    of: speech,
                    includePresenterNotes: options.includePresenterNotes,
                    includeSources: options.includeSources
                )
            )
        case .html:
            let content = text(
                of: speech,
                options: options,
                render: { SpeechTextRenderer.html(
                    of: $0,
                    includePresenterNotes: options.includePresenterNotes,
                    includeSources: options.includeSources
                ) }
            )
            return SpeechExportPayload(
                format: format,
                suggestedFileName: fileName,
                mimeType: format.mimeType,
                content: content,
                needsPDFRendering: false,
                previewText: SpeechTextRenderer.plainText(
                    of: speech,
                    includePresenterNotes: options.includePresenterNotes,
                    includeSources: options.includeSources
                )
            )
        case .pdf:
            // O PDF é renderizado no iOS a partir do HTML.
            let content = text(
                of: speech,
                options: options,
                render: { SpeechTextRenderer.html(
                    of: $0,
                    includePresenterNotes: options.includePresenterNotes,
                    includeSources: options.includeSources
                ) }
            )
            return SpeechExportPayload(
                format: format,
                suggestedFileName: fileName,
                mimeType: format.mimeType,
                content: content,
                needsPDFRendering: true,
                previewText: SpeechTextRenderer.plainText(
                    of: speech,
                    includePresenterNotes: options.includePresenterNotes,
                    includeSources: options.includeSources
                )
            )
        }
    }

    /// Gera o pedido de PDF para a camada iOS.
    public static func pdfRequest(
        for speech: Speech,
        options: SpeechExportOptions = .default
    ) throws -> SpeechPDFRequest {
        let payload = try payload(for: speech, format: .pdf, options: options)
        return SpeechPDFRequest(
            html: payload.content,
            suggestedFileName: payload.suggestedFileName,
            title: speech.displayTitle
        )
    }

    /// Renderiza com ou sem o bloco de metadados.
    private static func text(
        of speech: Speech,
        options: SpeechExportOptions,
        render: (Speech) -> String
    ) -> String {
        if options.includeMetadata {
            return render(speech)
        }
        var copy = speech
        copy.occasion = ""
        copy.plannedMinutes = nil
        copy.tags = []
        return render(copy)
    }
}
