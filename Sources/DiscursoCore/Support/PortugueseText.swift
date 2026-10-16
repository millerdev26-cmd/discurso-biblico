//
//  PortugueseText.swift
//  DiscursoCore
//
//  Normalização, tokenização e utilitários de texto para português do Brasil.
//
//  O ponto central é `FoldedText`: uma versão do texto original sem acentos e
//  em minúsculas, com um mapa de índices 1:1 de volta para o texto original.
//  Isso permite usar expressões regulares simples em ASCII (para reconhecer
//  "João", "Joao", "JOÃO", "joão" com um único padrão) e ainda assim devolver
//  os intervalos exatos no texto original, por exemplo para destacar a
//  referência bíblica na tela.
//
//  O mapa é 1:1 porque a normalização é feita caractere a caractere: cada
//  caractere original produz exatamente um caractere normalizado.
//

import Foundation

/// Texto normalizado (minúsculas, sem diacríticos) com mapeamento de índices
/// de volta para o texto original.
public struct FoldedText: Sendable {

    /// Texto original, exatamente como recebido.
    public let original: String

    /// Versão normalizada: minúsculas, sem acentos, mesmo número de caracteres.
    public let folded: String

    /// Índices dos caracteres do texto original (mesma contagem de `folded`).
    private let originalCharacters: [Character]

    public init(_ original: String) {
        self.original = original
        let characters = Array(original)
        self.originalCharacters = characters
        self.folded = String(characters.map(PortugueseText.foldCharacter))
    }

    /// Converte um intervalo do texto normalizado em intervalo do texto original.
    ///
    /// Retorna `nil` se o intervalo estiver fora dos limites.
    public func originalRange(forFolded range: Range<String.Index>) -> Range<String.Index>? {
        guard let startOffset = offset(of: range.lowerBound, in: folded),
              let endOffset = offset(of: range.upperBound, in: folded),
              startOffset >= 0, endOffset >= startOffset,
              endOffset <= originalCharacters.count
        else { return nil }

        let start = original.index(original.startIndex, offsetBy: startOffset)
        let end = original.index(original.startIndex, offsetBy: endOffset)
        return start..<end
    }

    /// Texto original correspondente a um intervalo do texto normalizado.
    public func originalSubstring(forFolded range: Range<String.Index>) -> String? {
        guard let originalRange = originalRange(forFolded: range) else { return nil }
        return String(original[originalRange])
    }

    /// Converte um intervalo expresso em deslocamentos de caracteres do texto
    /// normalizado para um intervalo do texto original.
    public func originalRange(foldedOffsets offsets: Range<Int>) -> Range<String.Index>? {
        guard offsets.lowerBound >= 0,
              offsets.upperBound >= offsets.lowerBound,
              offsets.upperBound <= originalCharacters.count
        else { return nil }
        let start = original.index(original.startIndex, offsetBy: offsets.lowerBound)
        let end = original.index(original.startIndex, offsetBy: offsets.upperBound)
        return start..<end
    }

    private func offset(of index: String.Index, in string: String) -> Int? {
        guard index >= string.startIndex, index <= string.endIndex else { return nil }
        return string.distance(from: string.startIndex, to: index)
    }
}

public enum PortugueseText {

    /// Normaliza um único caractere: minúsculo e sem diacríticos.
    ///
    /// Garantia importante: sempre devolve exatamente um `Character`, o que
    /// mantém o alinhamento 1:1 com o texto original. Diacríticos isolados
    /// (que aparecem sozinhos após a decomposição canônica) são descartados.
    ///
    /// A decomposição canônica (NFD) é obrigatória antes de filtrar: em
    /// "ú" pré-composto, o acento **não** é um escalar separado, portanto uma
    /// simples checagem de categoria não removeria nada.
    public static func foldCharacter(_ character: Character) -> Character {
        let decomposed = String(character)
            .decomposedStringWithCanonicalMapping
            .lowercased()
        var result = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                result.append(scalar)
            }
        }
        let filtered = String(result)
        if filtered.count == 1, let first = filtered.first {
            return first
        }
        if let recomposed = filtered.precomposedStringWithCanonicalMapping.first,
           filtered.precomposedStringWithCanonicalMapping.count == 1 {
            return recomposed
        }
        // Casos raros (letras que viram vazio ou mais de um caractere):
        // devolve o primeiro caractere para preservar o alinhamento 1:1.
        if let first = filtered.first {
            return first
        }
        return Character(" ")
    }

    /// Versão minúscula e sem acentos, útil para comparações.
    public static func folded(_ text: String) -> String {
        FoldedText(text).folded
    }

    /// Versão normalizada para busca: sem acentos, minúscula e com espaços
    /// múltiplos/linhas em branco colapsados em um único espaço.
    public static func normalizedForSearch(_ text: String) -> String {
        let folded = folded(text)
        var output = ""
        output.reserveCapacity(folded.count)
        var lastWasSpace = true
        for character in folded {
            if character.isWhitespace {
                if !lastWasSpace {
                    output.append(" ")
                    lastWasSpace = true
                }
            } else {
                output.append(character)
                lastWasSpace = false
            }
        }
        if output.hasSuffix(" ") {
            output.removeLast()
        }
        return output
    }

    /// Divide em tokens alfanuméricos normalizados (sem acentos, minúsculos).
    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        current.reserveCapacity(16)
        let folded = folded(text)
        for character in folded {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Número de palavras considerando apenas tokens com ao menos uma letra,
    /// o que ignora marcações como "1." ou "•" e números de referência.
    public static func wordCount(_ text: String) -> Int {
        tokenize(text).reduce(into: 0) { partial, token in
            if token.contains(where: { $0.isLetter }) {
                partial += 1
            } else {
                partial += 1
            }
        }
    }

    /// Número de palavras "reais" (>= 2 caracteres ou contendo letra), usado
    /// na estimativa de duração do discurso.
    public static func speakableWordCount(_ text: String) -> Int {
        tokenize(text).reduce(into: 0) { partial, token in
            if token.count >= 2 || token.contains(where: { $0.isLetter }) {
                partial += 1
            }
        }
    }

    /// Cria um trecho de contexto em volta de um intervalo, sem cortar palavras
    /// no meio e com reticências indicando continuidade.
    public static func snippet(
        in text: String,
        aroundOffset offset: Int,
        maximumLength: Int = 160
    ) -> String {
        guard !text.isEmpty else { return "" }
        let characters = Array(text)
        guard !characters.isEmpty else { return "" }

        let clampedOffset = max(0, min(offset, characters.count - 1))
        let half = max(10, maximumLength / 2)
        var start = max(0, clampedOffset - half)
        var end = min(characters.count, clampedOffset + half)

        // Ajusta para não começar/terminar no meio de uma palavra.
        while start > 0, characters[start - 1].isLetter || characters[start - 1].isNumber {
            start -= 1
        }
        while end < characters.count, characters[end].isLetter || characters[end].isNumber {
            end += 1
        }

        var snippet = String(characters[start..<end])
        snippet = snippet
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        while snippet.contains("  ") {
            snippet = snippet.replacingOccurrences(of: "  ", with: " ")
        }
        snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = start > 0 ? "… " : ""
        let suffix = end < characters.count ? " …" : ""
        return prefix + snippet + suffix
    }

    /// Primeira letra maiúscula, preservando o restante (uso em títulos).
    public static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }
}
