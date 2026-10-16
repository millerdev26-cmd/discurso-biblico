//
//  MarkdownBlocks.swift
//  DiscursoCore
//
//  Quebra um texto Markdown em blocos legíveis (título, parágrafo, lista,
//  citação, código), para o leitor do aplicativo mostrar o **conteúdo** e
//  não a marcação.
//
//  Por que existe: o leitor interno exibia o arquivo cru — "# Título",
//  "- item", "1. item" apareciam na tela. A indexação já usava
//  `MarkdownPlainText` (que joga a marcação fora), mas para *ler* era preciso
//  saber a estrutura: um título deve parecer título, uma lista deve ter
//  marcadores.
//
//  É um subconjunto deliberadamente pequeno do Markdown (o suficiente para
//  anotações de estudo e textos Bringing): títulos com `#`, listas com `-`,
//  `*`, `+` e `1.`, citações com `>`, cercas de código, linhas horizontais e
//  marcação embutida (ênfase, links, código). O que não for reconhecido
//  vira parágrafo — nunca some da tela.
//
//  Tudo aqui é Swift puro: os testes rodam em Linux (ver
//  Scripts/verify_app_logic.sh e Tests/DiscursoCoreTests).
//

/// Trecho de um texto Markdown já interpretado.
public enum MarkdownBlock: Hashable, Sendable {

    /// Título de nível 1 a 6 (`#` até `######`).
    case heading(level: Int, text: String)

    /// Tipo do bloco, sem os dados: útil para decidir estilo, validação e
    /// contagem sem precisar deconstructar cada caso.
    public enum Kind: String, Hashable, Sendable {
        case heading
        case paragraph
        case listItem
        case quote
        case code
        case rule
    }

    /// O tipo deste bloco.
    public var kind: Kind {
        switch self {
        case .heading: return .heading
        case .paragraph: return .paragraph
        case .listItem: return .listItem
        case .quote: return .quote
        case .code: return .code
        case .rule: return .rule
        }
    }

    /// Parágrafo comum.
    case paragraph(String)

    /// Item de lista com marcador (`-`, `*`, `+`) ou numerado (`1.`).
    case listItem(marker: MarkdownListMarker, text: String)

    /// Citação (`>`).
    case quote(String)

    /// Bloco de código entre cercas (```), sem a linguagem.
    case code(String)

    /// Linha horizontal (`---`).
    case rule
}

/// Tipo do marcador de um item de lista.
public enum MarkdownListMarker: Hashable, Sendable {
    case bullet
    case number(Int)

    /// Texto do marcador, como aparece na tela.
    public var displayText: String {
        switch self {
        case .bullet: return "•"
        case .number(let value): return "\(value)."
        }
    }
}

/// Interpretação de Markdown em blocos.
public enum MarkdownBlocks {

    /// Interpreta `markdown` e devolve os blocos na ordem do documento.
    ///
    /// Linhas vazias separam parágrafos; uma linha vazia dentro de um item de
    /// lista não fecha o item (listas com parágrafos continuam lendo).
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var fence: [String] = []
        var insideFence = false

        func flushParagraph() {
            let text = paragraph.joined(separator: " ")
            paragraph.removeAll()
            guard !text.isEmpty else { return }
            blocks.append(.paragraph(text))
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Cerca de código: ``` ou ~~~ (a linguagem na mesma linha da
            // cerca é aceita e ignorada; o conteúdo vem abaixo).
            if codeFenceMarker(line) != nil {
                if insideFence {
                    flushParagraph()
                    blocks.append(.code(fence.joined(separator: "\n")))
                    fence.removeAll()
                    insideFence = false
                } else {
                    flushParagraph()
                    insideFence = true
                }
                continue
            }
            if insideFence {
                fence.append(rawLine)
                continue
            }

            // Linha horizontal
            if isHorizontalRule(line) {
                flushParagraph()
                blocks.append(.rule)
                continue
            }

            // Título: até 6 '#' seguidos de espaço
            if line.hasPrefix("#") {
                let hashes = line.prefix(while: { $0 == "#" }).count
                let rest = line.dropFirst(hashes)
                if hashes <= 6, rest.hasPrefix(" ") || rest.isEmpty {
                    flushParagraph()
                    let title = inline(String(rest).trimmingCharacters(in: .whitespaces))
                    if !title.isEmpty {
                        blocks.append(.heading(level: hashes, text: title))
                    }
                    continue
                }
            }

            // Citação (pode ter ">" aninhado)
            var quote = line
            while quote.hasPrefix(">") {
                quote = String(quote.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if quote != line {
                flushParagraph()
                let text = inline(quote)
                if !text.isEmpty {
                    blocks.append(.quote(text))
                }
                continue
            }

            // Item de lista
            if let item = listItem(line) {
                flushParagraph()
                blocks.append(item)
                continue
            }

            if line.isEmpty {
                flushParagraph()
            } else {
                // Parágrafo: não mexe no começo da linha (um "#######" que não
                // é título continua texto), só limpa a marcação embutida.
                paragraph.append(MarkdownPlainText.stripInline(line))
            }
        }

        if insideFence {
            // Cerca de código sem fechamento: mostra o que houve, em vez de
            // perder o texto.
            let body = fence.joined(separator: "\n")
            if !body.isEmpty { blocks.append(.code(body)) }
        }
        flushParagraph()

        return blocks
    }

    /// Texto do documento sem a marcação, com um bloco por parágrafo/linha.
    ///
    /// É o mesmo conteúdo de `parse`, serializado — usado onde só interessa o
    /// texto (busca no conteúdo, cópia, leitura por voz).
    public static func plainText(from blocks: [MarkdownBlock]) -> String {
        blocks.compactMap { block in
            switch block {
            case .heading(_, let text), .paragraph(let text), .quote(let text):
                return text
            case .code(let text):
                return text
            case .listItem(let marker, let text):
                return "\(marker.displayText) \(text)"
            case .rule:
                return nil
            }
        }.joined(separator: "\n")
    }

    // MARK: - Reconhecimento

    private static func codeFenceMarker(_ line: String) -> String? {
        for marker in ["```", "~~~"] where line.hasPrefix(marker) {
            // O que vem depois da cerca é a linguagem ("```swift") e é
            // descartado: o leitor não colore código.
            let rest = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty || rest.range(of: #"^[A-Za-z0-9+#.-]{1,16}$"#, options: .regularExpression) != nil {
                return marker
            }
        }
        return nil
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard let symbol = compact.first, "-*_".contains(symbol) else { return false }
        return compact.allSatisfy { $0 == symbol }
    }

    private static func listItem(_ line: String) -> MarkdownBlock? {
        guard let range = line.range(
            of: #"^([-*+]|\d{1,3}[.)])\s+"#,
            options: .regularExpression
        ) else { return nil }
        let markerText = String(line[..<range.upperBound]).trimmingCharacters(in: .whitespaces)
        let content = inline(
            String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        )
        guard !content.isEmpty else { return nil }

        let marker: MarkdownListMarker
        if markerText.count > 1, let value = Int(markerText.dropLast()) {
            marker = .number(value)
        } else {
            marker = .bullet
        }
        return .listItem(marker: marker, text: content)
    }

    /// Aplica a marcação embutida: `código`, **ênfase forte**, *ênfase*,
    /// [texto](url) → "texto (url)" e imagens → texto alternativo.
    ///
    /// Reaproveita `MarkdownPlainText.stripInline` para não haver duas regras
    /// de limpeza que divergem com o tempo. O começo da linha já foi
    /// interpretado por quem chamou (título, lista, citação), então aqui só
    /// se remove a marcação **dentro** do texto.
    static func inline(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        return MarkdownPlainText.stripInline(trimmed)
            .trimmingCharacters(in: .whitespaces)
    }
}