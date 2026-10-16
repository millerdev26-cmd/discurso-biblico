//
//  SpeechTextRenderer.swift
//  DiscursoCore
//
//  Renderização de um discurso em texto simples, Markdown e HTML.
//
//  Esses formatos são a base da exportação (TXT, Markdown e o HTML usado para
//  gerar o PDF no iOS) e também alimentam a indexação local da biblioteca.
//  As marcações em linha são convertidas para os equivalentes de cada formato.
//

import Foundation

public enum SpeechTextRenderer {

    /// Texto simples, com títulos e listas legíveis.
    public static func plainText(
        of speech: Speech,
        includePresenterNotes: Bool = true,
        includeSources: Bool = false
    ) -> String {
        var lines: [String] = []
        lines.append(speech.displayTitle.uppercased())
        if !speech.subtitle.isEmpty { lines.append(speech.subtitle) }

        var metadata: [String] = []
        if !speech.occasion.isEmpty { metadata.append("Ocasião: \(speech.occasion)") }
        if let planned = speech.plannedMinutes {
            metadata.append("Duração planejada: \(Self.formatMinutes(planned))")
        }
        metadata.append("Duração estimada: \(speech.estimatedMinutes > 0 ? Self.formatMinutes(speech.estimatedMinutes) : "—")")
        if !speech.tags.isEmpty { metadata.append("Etiquetas: \(speech.tags.joined(separator: ", "))") }
        if !metadata.isEmpty {
            lines.append("")
            lines.append(metadata.joined(separator: " · "))
        }

        for (index, section) in speech.sections.enumerated() {
            lines.append("")
            let marker = section.isCompleted ? "[x]" : "[ ]"
            lines.append("\(index + 1). \(section.displayTitle) \(marker)")
            if !section.subtitle.isEmpty { lines.append("    \(section.subtitle)") }
            if let planned = section.plannedMinutes {
                lines.append("    (previsto: \(Self.formatMinutes(planned)))")
            }
            for block in section.blocks {
                if block.isPrivateContent, !includePresenterNotes { continue }
                lines.append(contentsOf: renderPlainBlock(block))
            }
            if includePresenterNotes, !section.privateNotes.isEmpty {
                lines.append("    Nota do tópico: \(section.privateNotes)")
            }
            if includeSources, !section.sources.isEmpty {
                lines.append("    Fontes:")
                for source in section.sources {
                    lines.append("      - \(source.displayTitle)\(source.url.map { " — \($0.absoluteString)" } ?? "")")
                }
            }
        }

        if includePresenterNotes, !speech.privateNotes.isEmpty {
            lines.append("")
            lines.append("NOTAS PRIVADAS")
            lines.append(speech.privateNotes)
        }

        return lines.joined(separator: "\n")
    }

    private static func renderPlainBlock(_ block: SpeechBlock) -> [String] {
        switch block.kind {
        case .divider:
            return ["    ————————"]
        case .bulletList:
            return block.items.map { "    • \(InlineMarkup.plainText($0))" }
        case .heading:
            return ["", "    ## \(InlineMarkup.plainText(block.text))"]
        case .subheading:
            return ["    ### \(InlineMarkup.plainText(block.text))"]
        case .quote:
            return block.text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "    | \(InlineMarkup.plainText(String($0)))" }
        case .scripture:
            var lines: [String] = []
            if let reference = block.reference {
                lines.append("    📖 \(reference.displayText)")
            }
            if !block.text.isEmpty {
                lines.append(contentsOf: block.text.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "    \"\(InlineMarkup.plainText(String($0)))\"" })
            }
            return lines
        case .note:
            return ["", "    Nota: \(InlineMarkup.plainText(block.text))"]
        case .cue:
            let detail = block.cueDetail.map { ": \($0)" } ?? ""
            return ["    ⟶ \(block.cue?.displayName ?? "Indicação")\(detail)"]
        case .paragraph:
            let prefix = block.isPresenterNote ? "    Nota: " : "    "
            return block.text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "\(prefix)\(InlineMarkup.plainText(String($0)))" }
        }
    }

    /// Markdown estruturado, com preservação de títulos, seções, referências,
    /// notas e fontes.
    public static func markdown(
        of speech: Speech,
        includePresenterNotes: Bool = true,
        includeSources: Bool = true
    ) -> String {
        var lines: [String] = []
        lines.append("# \(speech.displayTitle)")
        if !speech.subtitle.isEmpty { lines.append("_\(speech.subtitle)_") }
        lines.append("")

        var metadata: [String] = []
        if !speech.occasion.isEmpty { metadata.append("**Ocasião:** \(speech.occasion)") }
        if let planned = speech.plannedMinutes {
            metadata.append("**Duração planejada:** \(Self.formatMinutes(planned))")
        }
        metadata.append("**Duração estimada:** \(Self.formatMinutes(speech.estimatedMinutes))")
        if !metadata.isEmpty {
            lines.append(contentsOf: metadata.map { "- \($0)" })
            lines.append("")
        }
        if !speech.tags.isEmpty {
            lines.append("**Etiquetas:** \(speech.tags.map { "`\($0)`" }.joined(separator: " "))")
            lines.append("")
        }

        for (index, section) in speech.sections.enumerated() {
            lines.append("## \(index + 1). \(section.displayTitle)\(section.isCompleted ? " ✅" : "")")
            if !section.subtitle.isEmpty { lines.append("### \(section.subtitle)") }
            if let planned = section.plannedMinutes {
                lines.append("*Tempo previsto: \(Self.formatMinutes(planned))*")
            }
            lines.append("")
            for block in section.blocks {
                if block.isPrivateContent, !includePresenterNotes { continue }
                lines.append(contentsOf: renderMarkdownBlock(block))
            }
            if includePresenterNotes, !section.privateNotes.isEmpty {
                lines.append("> **Nota do tópico:** \(section.privateNotes)")
                lines.append("")
            }
            if includeSources, !section.sources.isEmpty {
                lines.append("**Fontes:**")
                for source in section.sources {
                    let url = source.url.map { " <\($0.absoluteString)>" } ?? ""
                    lines.append("- \(source.displayTitle)\(url)")
                }
                lines.append("")
            }
        }

        if includePresenterNotes, !speech.privateNotes.isEmpty {
            lines.append("---")
            lines.append("")
            lines.append("### Notas privadas")
            lines.append("")
            lines.append(speech.privateNotes)
        }

        return lines.joined(separator: "\n")
    }

    private static func renderMarkdownBlock(_ block: SpeechBlock) -> [String] {
        switch block.kind {
        case .divider:
            return ["---", ""]
        case .bulletList:
            return block.items.map { "- \(InlineMarkup.plainText($0))" } + [""]
        case .heading:
            return ["### \(InlineMarkup.plainText(block.text))", ""]
        case .subheading:
            return ["#### \(InlineMarkup.plainText(block.text))", ""]
        case .quote:
            return block.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \(InlineMarkup.plainText(String($0)))" } + [""]
        case .scripture:
            var lines: [String] = []
            if let reference = block.reference {
                lines.append("**📖 \(reference.displayText)**")
                if let url = reference.officialWebURL() {
                    lines.append("[Consultar na fonte oficial](\(url.absoluteString))")
                }
            }
            if !block.text.isEmpty {
                lines.append(contentsOf: block.text.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "> \(InlineMarkup.plainText(String($0)))" })
            }
            lines.append("")
            return lines
        case .note:
            return ["> **Nota:** \(InlineMarkup.plainText(block.text))", ""]
        case .cue:
            let detail = block.cueDetail.map { ": \($0)" } ?? ""
            return ["`⟶ \(block.cue?.displayName ?? "Indicação")\(detail)`", ""]
        case .paragraph:
            let prefix = block.isPresenterNote ? "> **Nota:** " : ""
            return block.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "\(prefix)\(InlineMarkup.plainText(String($0)))" } + [""]
        }
    }

    /// HTML simples e autocontido (usado para gerar o PDF no iOS e para
    /// compartilhar).
    public static func html(
        of speech: Speech,
        includePresenterNotes: Bool = true,
        includeSources: Bool = true
    ) -> String {
        var body: [String] = []
        body.append("<h1>\(escape(speech.displayTitle))</h1>")
        if !speech.subtitle.isEmpty { body.append("<p class=\"subtitle\">\(escape(speech.subtitle))</p>") }

        var metadata: [String] = []
        if !speech.occasion.isEmpty { metadata.append("<strong>Ocasião:</strong> \(escape(speech.occasion))") }
        if let planned = speech.plannedMinutes {
            metadata.append("<strong>Duração planejada:</strong> \(Self.formatMinutes(planned))")
        }
        metadata.append("<strong>Duração estimada:</strong> \(Self.formatMinutes(speech.estimatedMinutes))")
        body.append("<p class=\"meta\">\(metadata.joined(separator: " · "))</p>")

        for (index, section) in speech.sections.enumerated() {
            body.append("<h2>\(index + 1). \(escape(section.displayTitle))\(section.isCompleted ? " ✅" : "")</h2>")
            if !section.subtitle.isEmpty { body.append("<h3>\(escape(section.subtitle))</h3>") }
            for block in section.blocks {
                if block.isPrivateContent, !includePresenterNotes { continue }
                body.append(contentsOf: renderHTMLBlock(block))
            }
            if includePresenterNotes, !section.privateNotes.isEmpty {
                body.append("<div class=\"note\"><strong>Nota do tópico:</strong> \(escape(section.privateNotes))</div>")
            }
            if includeSources, !section.sources.isEmpty {
                body.append("<div class=\"sources\"><strong>Fontes:</strong><ul>")
                for source in section.sources {
                    let url = source.url.map { " — <a href=\"\($0.absoluteString)\">\(escape($0.absoluteString))</a>" } ?? ""
                    body.append("<li>\(escape(source.displayTitle))\(url)</li>")
                }
                body.append("</ul></div>")
            }
        }

        if includePresenterNotes, !speech.privateNotes.isEmpty {
            body.append("<hr/><h2>Notas privadas</h2><p>\(escape(speech.privateNotes))</p>")
        }

        return """
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
        <meta charset="utf-8"/>
        <title>\(escape(speech.displayTitle))</title>
        <style>
        \(defaultStylesheet)
        </style>
        </head>
        <body>
        \(body.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    private static func renderHTMLBlock(_ block: SpeechBlock) -> [String] {
        switch block.kind {
        case .divider:
            return ["<hr/>"]
        case .bulletList:
            let items = block.items.map { "<li>\(escape(InlineMarkup.plainText($0)))</li>" }.joined()
            return ["<ul>\(items)</ul>"]
        case .heading:
            return ["<h3>\(escape(InlineMarkup.plainText(block.text)))</h3>"]
        case .subheading:
            return ["<h4>\(escape(InlineMarkup.plainText(block.text)))</h4>"]
        case .quote:
            return ["<blockquote>\(escape(InlineMarkup.plainText(block.text)))</blockquote>"]
        case .scripture:
            var parts: [String] = []
            if let reference = block.reference {
                let link = reference.officialWebURL().map { " <a href=\"\($0.absoluteString)\">(fonte oficial)</a>" } ?? ""
                parts.append("<p class=\"scripture\"><strong>📖 \(escape(reference.displayText))</strong>\(link)</p>")
            }
            if !block.text.isEmpty {
                parts.append("<blockquote>\(escape(InlineMarkup.plainText(block.text)))</blockquote>")
            }
            return parts
        case .note:
            return ["<div class=\"note\"><strong>Nota:</strong> \(escape(InlineMarkup.plainText(block.text)))</div>"]
        case .cue:
            let detail = block.cueDetail.map { ": \($0)" } ?? ""
            return ["<p class=\"cue\">⟶ \(escape((block.cue?.displayName ?? "Indicação") + detail))</p>"]
        case .paragraph:
            let prefix = block.isPresenterNote ? "<strong>Nota:</strong> " : ""
            return ["<p>\(prefix)\(escape(InlineMarkup.plainText(block.text)))</p>"]
        }
    }

    /// Folha de estilo usada na geração de PDF e na visualização prévia.
    public static let defaultStylesheet = """
    body { font-family: -apple-system, "Georgia", serif; font-size: 15px; line-height: 1.5;
           color: #1a1a1a; margin: 40px auto; max-width: 640px; padding: 0 16px; }
    h1 { font-size: 24px; margin-bottom: 4px; }
    h2 { font-size: 19px; margin-top: 28px; border-bottom: 1px solid #ddd; padding-bottom: 4px; }
    h3 { font-size: 17px; margin-top: 20px; }
    h4 { font-size: 16px; margin-top: 16px; color: #333; }
    p.subtitle { font-style: italic; color: #555; margin-top: 0; }
    p.meta { color: #555; font-size: 13px; }
    .note { background: #f4f4f2; border-left: 3px solid #b7b7a4; padding: 8px 12px;
            margin: 12px 0; font-size: 14px; color: #333; }
    .cue { color: #6b705c; font-style: italic; margin: 8px 0; }
    .scripture { background: #f7f7f5; padding: 8px 12px; border-radius: 6px; }
    blockquote { border-left: 3px solid #d8d8d8; margin: 12px 0; padding-left: 12px; color: #333; }
    .sources { font-size: 13px; color: #555; }
    ul { margin-top: 4px; }
    """

    /// Nome de arquivo sugerido para exportações.
    public static func suggestedFileName(for speech: Speech, extension fileExtension: String) -> String {
        var name = speech.displayTitle
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines)
        name = name.components(separatedBy: invalid).joined(separator: "-")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "discurso" }
        if name.count > 80 { name = String(name.prefix(80)) }
        return "\(name).\(fileExtension)"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br/>")
    }

    private static func formatMinutes(_ minutes: Double) -> String {
        let totalSeconds = Int((minutes * 60).rounded())
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }
}
