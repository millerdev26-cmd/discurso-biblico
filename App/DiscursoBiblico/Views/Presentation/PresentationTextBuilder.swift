//
//  PresentationTextBuilder.swift
//  DiscursoBiblico
//
//  Monta o texto que aparece no modo de proferimento.
//
//  Regras:
//   - títulos em destaque; parágrafos com o espaçamento escolhido;
//   - marcações de orador (CueKind) aparecem como orientações discretas;
//   - observações particulares só aparecem se o usuário pedir;
//   - referências bíblicas recebem uma ligação interna (tocar abre o painel
//     do trecho, sem perder a posição do discurso);
//   - tema, fonte, alinhamento e destaque saem das preferências.
//

import DiscursoCore
import UIKit

/// Cores do modo de apresentação por tema.
struct PresentationPalette {

    var background: UIColor
    var text: UIColor
    var secondary: UIColor
    var accent: UIColor
    var cue: UIColor
    var note: UIColor

    static func palette(for theme: ReadingTheme, traits: UITraitCollection) -> PresentationPalette {
        let isDark = traits.userInterfaceStyle == .dark
        switch theme {
        case .system:
            return isDark ? dark : light
        case .light:
            return light
        case .dark:
            return dark
        case .sepia:
            return sepia
        case .highContrast:
            return highContrast
        }
    }

    static let light = PresentationPalette(
        background: UIColor(white: 0.99, alpha: 1),
        text: UIColor(white: 0.08, alpha: 1),
        secondary: UIColor(white: 0.42, alpha: 1),
        accent: UIColor(red: 0.08, green: 0.36, blue: 0.62, alpha: 1),
        cue: UIColor(red: 0.55, green: 0.25, blue: 0.05, alpha: 1),
        note: UIColor(white: 0.45, alpha: 1)
    )

    static let dark = PresentationPalette(
        background: UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1),
        text: UIColor(white: 0.93, alpha: 1),
        secondary: UIColor(white: 0.68, alpha: 1),
        accent: UIColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1),
        cue: UIColor(red: 1.0, green: 0.78, blue: 0.48, alpha: 1),
        note: UIColor(white: 0.62, alpha: 1)
    )

    static let sepia = PresentationPalette(
        background: UIColor(red: 0.965, green: 0.937, blue: 0.867, alpha: 1),
        text: UIColor(red: 0.22, green: 0.184, blue: 0.13, alpha: 1),
        secondary: UIColor(red: 0.42, green: 0.36, blue: 0.27, alpha: 1),
        accent: UIColor(red: 0.45, green: 0.28, blue: 0.08, alpha: 1),
        cue: UIColor(red: 0.55, green: 0.30, blue: 0.05, alpha: 1),
        note: UIColor(red: 0.45, green: 0.39, blue: 0.30, alpha: 1)
    )

    static let highContrast = PresentationPalette(
        background: .black,
        text: .white,
        secondary: UIColor(white: 0.85, alpha: 1),
        accent: UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1),
        cue: UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1),
        note: UIColor(white: 0.8, alpha: 1)
    )
}

/// Constrói o texto atribuído do discurso para apresentação.
struct PresentationTextBuilder {

    let speech: Speech
    let preferences: PresentationPreferences

    struct Result {
        var attributedText: NSAttributedString
        /// Faixa de caracteres de cada tópico (para medir e navegar).
        var sectionRanges: [NSRange]
    }

    private var palette: PresentationPalette {
        PresentationPalette.palette(for: preferences.theme, traits: UITraitCollection.current)
    }

    func build() -> Result {
        let output = NSMutableAttributedString()
        var ranges: [NSRange] = []

        for (index, section) in speech.sections.enumerated() {
            let start = output.length
            if index > 0 {
                output.append(
                    NSAttributedString(
                        string: "\n",
                        attributes: [.paragraphStyle: paragraphStyle()]
                    )
                )
            }
            for block in section.blocks where shouldShow(block) {
                output.append(attributed(block))
            }
            ranges.append(NSRange(location: start, length: max(0, output.length - start)))
        }

        return Result(attributedText: output, sectionRanges: ranges)
    }

    // MARK: Blocos

    private func shouldShow(_ block: SpeechBlock) -> Bool {
        // Conteúdo particular (nota do apresentador ou bloco "observação")
        // só aparece quando o usuário pedir.
        if block.isPrivateContent { return preferences.showsPresenterNotes }
        return true
    }

    private func attributed(_ block: SpeechBlock) -> NSAttributedString {
        let text = rawText(of: block)
        let string = NSMutableAttributedString(string: text, attributes: attributes(for: block))
        if preferences.highlightsReferences {
            decorateReferences(in: string, block: block)
        }
        return string
    }

    private func rawText(of block: SpeechBlock) -> String {
        // As marcações em linha (*ênfase*, {pausa}, {tom: ...}) são orientações
        // de preparação: na apresentação o texto sai limpo, do mesmo modo que
        // na exportação e na estimativa de duração (`InlineMarkup.plainText`).
        switch block.kind {
        case .heading:
            let title = block.text.isEmpty ? "Tópico" : InlineMarkup.plainText(block.text)
            return title + "\n"
        case .subheading:
            return InlineMarkup.plainText(block.text) + "\n"
        case .quote:
            return "“\(InlineMarkup.plainText(block.text))”\n"
        case .bulletList:
            guard !block.items.isEmpty else { return "" }
            return block.items.map { "•  \(InlineMarkup.plainText($0))" }.joined(separator: "\n") + "\n"
        case .note:
            let detail = block.cueDetail.map { ": \($0)" } ?? ""
            let cueText = (block.cue?.displayName ?? "Marcação") + detail
            return "[\(cueText)]\n"
        case .divider:
            return "· · ·\n"
        case .cue:
            let detail = block.cueDetail.map { ": \($0)" } ?? ""
            let cueText = (block.cue?.displayName ?? "Marcação") + detail
            return "[\(cueText)]\n"
        case .scripture:
            let reference = block.reference?.displayText ?? ""
            let text = InlineMarkup.plainText(block.text)
            if text.isEmpty { return reference + "\n" }
            return reference.isEmpty ? text + "\n" : "\(reference) — \(text)\n"
        case .paragraph:
            return InlineMarkup.plainText(block.text) + "\n"
        }
    }

    private func attributes(for block: SpeechBlock) -> [NSAttributedString.Key: Any] {
        let colors = palette
        var attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle(for: block),
            .foregroundColor: colors.text
        ]

        switch block.kind {
        case .heading:
            attributes[.font] = font(sizeMultiplier: 1.22, bold: true)
            attributes[.foregroundColor] = colors.accent
        case .subheading:
            attributes[.font] = font(sizeMultiplier: 1.08, bold: true)
            attributes[.foregroundColor] = colors.secondary
        case .quote:
            attributes[.font] = italicFont(sizeMultiplier: 1.0)
            attributes[.foregroundColor] = colors.secondary
        case .note:
            attributes[.font] = italicFont(sizeMultiplier: 0.9)
            attributes[.foregroundColor] = colors.note
        case .cue:
            attributes[.font] = font(sizeMultiplier: 0.82, bold: false)
            attributes[.foregroundColor] = colors.cue
        case .divider:
            attributes[.font] = font(sizeMultiplier: 1.0, bold: false)
            attributes[.foregroundColor] = colors.secondary
        case .scripture:
            attributes[.font] = italicFont(sizeMultiplier: 1.0)
        case .bulletList:
            attributes[.font] = font(sizeMultiplier: 1.0, bold: preferences.usesBoldText)
        case .paragraph:
            attributes[.font] = font(sizeMultiplier: 1.0, bold: preferences.usesBoldText)
        }

        if block.isPresenterNote {
            attributes[.foregroundColor] = colors.note
            attributes[.font] = italicFont(sizeMultiplier: 0.9)
        }
        if block.isHighlighted {
            attributes[.backgroundColor] = colors.accent.withAlphaComponent(0.14)
        }
        return attributes
    }

    private func paragraphStyle(for block: SpeechBlock? = nil) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = CGFloat(preferences.lineHeightMultiple)
        paragraph.paragraphSpacing = CGFloat(preferences.paragraphSpacing) * CGFloat(preferences.fontSize) * 0.5
        paragraph.alignment = {
            switch preferences.alignment {
            case .leading: return .natural
            case .justified: return .justified
            case .center: return .center
            }
        }()
        if let block, block.kind == .bulletList {
            paragraph.headIndent = CGFloat(preferences.fontSize) * 0.9
            paragraph.firstLineHeadIndent = 0
        }
        return paragraph
    }

    // MARK: Referências

    private func decorateReferences(in string: NSMutableAttributedString, block: SpeechBlock) {
        var references = block.referencesInText
        if let reference = block.reference, !references.contains(where: { $0 == reference }) {
            references.insert(reference, at: 0)
        }
        guard !references.isEmpty else { return }
        let full = string.string as NSString

        for reference in references {
            guard let url = BibleReferenceLink.url(for: reference) else { continue }
            let needle = reference.displayText
            var searchRange = NSRange(location: 0, length: full.length)
            while searchRange.length > 0 {
                let found = full.range(
                    of: needle,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )
                guard found.location != NSNotFound else { break }
                string.addAttributes([
                    .link: url,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: palette.accent
                ], range: found)
                let next = found.location + max(1, found.length)
                guard next < full.length else { break }
                searchRange = NSRange(location: next, length: full.length - next)
            }
        }
    }

    // MARK: Fontes

    private func font(sizeMultiplier: Double, bold: Bool) -> UIFont {
        let pointSize = CGFloat(preferences.fontSize * sizeMultiplier)
        let weight: UIFont.Weight = bold || preferences.usesBoldText ? .semibold : .regular
        let base = UIFont.systemFont(ofSize: pointSize, weight: weight)
        var configured = base
        switch preferences.fontDesign {
        case .system:
            break
        case .serif:
            configured = descriptor(base, design: .serif)
        case .rounded:
            configured = descriptor(base, design: .rounded)
        case .monospaced:
            configured = descriptor(base, design: .monospaced)
        }
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: configured, maximumPointSize: 120)
    }

    private func italicFont(sizeMultiplier: Double) -> UIFont {
        let pointSize = CGFloat(preferences.fontSize * sizeMultiplier)
        let base = UIFont.italicSystemFont(ofSize: pointSize)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base, maximumPointSize: 120)
    }

    private func descriptor(_ font: UIFont, design: UIFontDescriptor.SystemDesign) -> UIFont {
        guard let descriptor = font.fontDescriptor.withDesign(design) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
