//
//  BibleReferenceParser.swift
//  DiscursoCore
//
//  Reconhecimento de referências bíblicas em textos em português.
//
//  Estratégia: o texto é normalizado uma vez (minúsculas, sem acentos) com um
//  mapa 1:1 de índices de volta ao texto original. Sobre a versão normalizada,
//  um scanner de varredura única reconhece:
//
//    * nomes completos e abreviações ............ "João", "Jo", "João.", "Mt",
//                                                 "Gên.", "Sal.", "1Co"
//    * ordinais ................................ "1 João", "1ª João", "I Coríntios",
//                                                 "Segunda Timóteo", "1Coríntios"
//    * capítulo e versículo .................... "3:16", "3.16", "capítulo 3 v. 16",
//                                                 "cap. 3 vers. 16", "3"
//    * versículos múltiplos .................... "12:1, 2", "13:4-7", "13:4-7, 9"
//    * faixas com "a" e travessões ............. "16-18", "16 – 18", "16 a 18"
//    * versículos parciais ..................... "16a", "16b"
//    * continuação de capítulos ................ "João 3:16; 4:2", "João 3:16, 4:2"
//
//  Várias referências no mesmo parágrafo são reconhecidas separadamente, com
//  os intervalos exatos preservados para destaque na tela.
//
//  Heurísticas documentadas (ver docs/DECISOES.md):
//   - "jo" é resolvido pelo acento: "Jó" -> Jó; "Jo"/"João" -> Evangelho.
//   - Apelidos que colidem com palavras comuns do português ("na", "os", "am",
//     "is", "at", "la") só valem se escritos com inicial maiúscula ou seguidos
//     de ponto ("Na 3:1", "Os. 2:3").
//   - Um número de versículo nunca é aceito se for seguido de ":" — isso evita
//     ler "João 3:16 e 4:2" como se "4" fosse versículo.
//   - "João 25:1" não é aceito porque João tem 21 capítulos (validação pelo
//     catálogo). A validação de versículos depende do texto bíblico carregado.
//

import Foundation

/// Uma ocorrência de referência bíblica dentro de um texto.
public struct BibleReferenceMatch: Hashable, Sendable {
    /// Referência estruturada reconhecida.
    public let reference: BibleReference
    /// Intervalo no texto **original** (pronto para destacar na interface).
    public let range: Range<String.Index>
    /// Trecho exato do texto original que gerou a referência.
    public let matchedText: String

    public init(reference: BibleReference, range: Range<String.Index>, matchedText: String) {
        self.reference = reference
        self.range = range
        self.matchedText = matchedText
    }
}

public enum BibleReferenceParser {

    /// Todos os apelidos, agrupados pela primeira letra e ordenados do mais
    /// longo para o mais curto (garante que "cantico de salomao" vença "can").
    private static let aliasTable: [Character: [(alias: String, characters: [Character])]] = {
        var table: [Character: [(String, [Character])]] = [:]
        for alias in BibleBookCatalog.allAliasesLongestFirst {
            guard let first = alias.first else { continue }
            table[first, default: []].append((alias, Array(alias)))
        }
        for key in table.keys {
            table[key]?.sort { lhs, rhs in
                if lhs.0.count != rhs.0.count { return lhs.0.count > rhs.0.count }
                return lhs.0 < rhs.0
            }
        }
        return table
    }()

    /// Apelidos que também são palavras comuns em português e por isso exigem
    /// inicial maiúscula (ou ponto logo depois) para serem aceitos.
    private static let riskyAliases: Set<String> = ["na", "os", "am", "is", "at", "la"]

    private static let ordinalWords: [(word: String, value: Int)] = [
        ("primeira", 1), ("primeiro", 1), ("segunda", 2), ("segundo", 2),
        ("terceira", 3), ("terceiro", 3)
    ]

    private static let chapterKeywords = ["capitulo", "capitulos", "cap", "caps"]
    private static let verseKeywords = ["versiculo", "versiculos", "vers", "v"]

    // MARK: - API pública

    /// Encontra todas as referências bíblicas do texto, em ordem e sem sobreposição.
    public static func matches(in text: String) -> [BibleReferenceMatch] {
        guard !text.isEmpty else { return [] }
        let foldedText = FoldedText(text)
        var scanner = Scanner(foldedText: foldedText)
        return scanner.scan()
    }

    /// Primeira ocorrência encontrada, se houver.
    public static func firstMatch(in text: String) -> BibleReferenceMatch? {
        matches(in: text).first
    }

    /// Referências únicas (sem repetição) preservando a ordem de aparição.
    public static func uniqueReferences(in text: String) -> [BibleReference] {
        var seen = Set<BibleReference>()
        var result: [BibleReference] = []
        for match in matches(in: text) where !seen.contains(match.reference) {
            seen.insert(match.reference)
            result.append(match.reference)
        }
        return result
    }

    /// Interpreta o texto inteiro como uma referência bíblica.
    ///
    /// Usado no campo de pesquisa por referência: "João 3:16" devolve a
    /// referência; "João 3:16 e outras coisas" devolve `nil` porque o texto
    /// completo não é apenas uma referência.
    public static func parseWhole(_ text: String) -> BibleReference? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let match = firstMatch(in: trimmed) else { return nil }
        let matched = match.matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PortugueseText.folded(matched) == PortugueseText.folded(trimmed) else { return nil }
        return match.reference
    }

    /// Interprete o começo do texto como referência, devolvendo também o que
    /// sobrou (útil para autocompletar enquanto o usuário digita).
    public static func parsePrefix(_ text: String) -> (reference: BibleReference, remainder: String)? {
        guard let match = firstMatch(in: text) else { return nil }
        guard match.range.lowerBound == text.startIndex else { return nil }
        return (match.reference, String(text[match.range.upperBound...]))
    }

    // MARK: - Scanner

    /// Varredura única sobre o texto normalizado.
    private struct Scanner {
        let foldedText: FoldedText
        /// Caracteres normalizados (1:1 com o original).
        let characters: [Character]
        /// Caracteres originais, usados para heurísticas de maiúscula/acento.
        let originalCharacters: [Character]

        init(foldedText: FoldedText) {
            self.foldedText = foldedText
            self.characters = Array(foldedText.folded)
            self.originalCharacters = Array(foldedText.original)
        }

        var count: Int { characters.count }

        func isLetterOrNumber(_ character: Character) -> Bool {
            character.isLetter || character.isNumber
        }

        mutating func scan() -> [BibleReferenceMatch] {
            var results: [BibleReferenceMatch] = []
            var index = 0

            while index < count {
                if let match = attemptMatch(at: index) {
                    results.append(match)
                    index = endOffset(of: match)
                } else {
                    index += 1
                }
            }
            return results
        }

        private func endOffset(of match: BibleReferenceMatch) -> Int {
            let end = match.range.upperBound
            return foldedText.original.distance(from: foldedText.original.startIndex, to: end)
        }

        /// Tenta reconhecer uma referência começando exatamente em `start`.
        private func attemptMatch(at start: Int) -> BibleReferenceMatch? {
            guard start < count else { return nil }
            // Fronteira à esquerda: não pode estar no meio de uma palavra/número.
            if start > 0, isLetterOrNumber(characters[start - 1]) { return nil }
            guard characters[start].isLetter || characters[start].isNumber else { return nil }

            // Ordem de tentativa do ordinal: com ordinal, depois sem ordinal.
            // "1 João 4:8" tenta (1, jonh) e também (joão) — o primeiro sucesso vence.
            for ordinalAttempt in [true, false] {
                if ordinalAttempt {
                    guard let afterOrdinal = parseOrdinal(at: start) else { continue }
                    if let match = parseReference(afterBookStartCandidate: start, ordinal: afterOrdinal.value, ordinalEnd: afterOrdinal.end) {
                        return match
                    }
                } else if let match = parseReference(afterBookStartCandidate: start, ordinal: nil, ordinalEnd: start) {
                    return match
                }
            }
            return nil
        }

        /// Tenta ler um ordinal antes do nome do livro.
        ///
        /// Aceita "1", "2", "3", "1º", "1ª", "1o", "1a", "I", "II", "III",
        /// "Primeira", "Segunda", "Terceira" — sempre exigindo que o nome do
        /// livro venha em seguida.
        private func parseOrdinal(at start: Int) -> (value: Int, end: Int)? {
            var index = start

            // Forma numérica: 1, 2, 3 (nunca 4+ : não existem grupos assim).
            if characters[index].isNumber {
                let digit = characters[index]
                guard let value = digit.wholeNumberValue, (1...3).contains(value) else { return nil }
                index += 1
                // Sufixos ordinais opcionais: º, ª, °, o, a (com ponto opcional,
                // mas nunca depois de "o"/"a" colados em outra palavra).
                if index < count, ["º", "ª", "°"].contains(characters[index]) {
                    index += 1
                } else if index < count, characters[index] == "o" || characters[index] == "a" {
                    let next = index + 1
                    if next < count, characters[next] == "." || characters[next] == " " {
                        index += 1
                    }
                }
                guard let after = consumeBookSeparator(at: index) else { return nil }
                return (value, after)
            }

            // Forma romana: i, ii, iii (exige espaço depois, para não consumir "is").
            if characters[index] == "i" {
                var scanIndex = index
                var romanCount = 0
                while scanIndex < count, characters[scanIndex] == "i", romanCount < 3 {
                    romanCount += 1
                    scanIndex += 1
                }
                if romanCount > 0, scanIndex < count, characters[scanIndex] == " " {
                    let afterWord = skipSpaces(from: scanIndex)
                    if afterWord < count, characters[afterWord] == "." {
                        let afterDot = skipSpaces(from: afterWord + 1)
                        if afterDot < count, originalCharacters[afterDot].isUppercase {
                            return (romanCount, afterDot)
                        }
                    }
                    return (romanCount, afterWord)
                }
            }

            // Formas por extenso: "primeira", "segundo", "terceira".
            for word in ordinalWords {
                guard let end = matchWord(word.word, at: index), end < count, characters[end] == " " else { continue }
                let afterWord = skipSpaces(from: end)
                guard afterWord < count else { continue }
                return (word.value, afterWord)
            }

            return nil
        }

        /// Consome espaços e um ponto opcional depois do ordinal numérico,
        /// devolvendo a posição onde o nome do livro deve começar.
        private func consumeBookSeparator(at start: Int) -> Int? {
            var index = start
            if index < count, characters[index] == "." {
                // "1. Coríntios" só é aceito se o nome começar com maiúscula:
                // caso contrário é um marcador de lista ("1. o texto...").
                let afterDot = skipSpaces(from: index + 1)
                guard afterDot < count, originalCharacters[afterDot].isUppercase else { return nil }
                index = afterDot
            } else {
                index = skipSpaces(from: index)
            }
            guard index < count else { return nil }
            return index
        }

        /// Lê o nome do livro, capítulos, versículos e partes subsequentes.
        ///
        /// - Parameters:
        ///   - start: posição original da tentativa (usada para validar a
        ///     fronteira e para a heurística de acento).
        ///   - ordinal: ordinal já lido, se houver.
        ///   - ordinalEnd: posição onde o nome do livro deve começar.
        private func parseReference(
            afterBookStartCandidate start: Int,
            ordinal: Int?,
            ordinalEnd: Int
        ) -> BibleReferenceMatch? {
            guard let bookMatch = matchBookAlias(at: ordinalEnd) else { return nil }

            var index = bookMatch.end
            index = skipSpaces(from: index)
            // Ponto depois do nome: "Mt. 24:14", "João. 3:16".
            if index < count, characters[index] == "." {
                index = skipSpaces(from: index + 1)
            }

            // "capítulo 3", "cap. 3", "caps. 3"
            if let afterKeyword = consumeKeyword(chapterKeywords, at: index) {
                index = skipSpaces(from: afterKeyword)
            }

            guard let chapterParse = parseNumber(at: index, maxDigits: 3) else { return nil }
            index = chapterParse.end

            guard let book = BibleBookCatalog.resolve(
                alias: bookMatch.alias,
                ordinal: ordinal,
                originalSpelling: originalSpelling(from: ordinalEnd, to: bookMatch.end)
            ) else { return nil }

            guard BibleBookCatalog.isValidChapter(chapterParse.value, in: book.id) else { return nil }

            var parts: [BibleReferencePart] = []

            // Versículos da primeira parte.
            var verses: [BibleVerseRange] = []
            if let verseParse = parseVerseList(at: index) {
                verses = verseParse.ranges
                index = verseParse.end
            }
            parts.append(BibleReferencePart(chapter: chapterParse.value, verses: verses))

            // Continuações: "João 3:16; 4:2" ou "João 3:16, 4:2".
            while let continuation = parseContinuationPart(at: index, book: book) {
                parts.append(continuation.part)
                index = continuation.end
            }

            let reference = BibleReference(bookID: book.id, parts: parts)
            guard reference.isValid() else { return nil }

            guard let originalRange = foldedText.originalRange(foldedOffsets: start..<index) else { return nil }
            let matchedText = String(foldedText.original[originalRange])
            return BibleReferenceMatch(reference: reference, range: originalRange, matchedText: matchedText)
        }

        /// Próxima parte depois de ";" (ou "," e " e " quando vier
        /// "capítulo:versículo", o que indica novo capítulo).
        private func parseContinuationPart(
            at start: Int,
            book: BibleBookInfo
        ) -> (part: BibleReferencePart, end: Int)? {
            var index = skipSpaces(from: start)
            guard index < count else { return nil }

            var separatorKind: Separator = .none
            if characters[index] == ";" {
                separatorKind = .semicolon
                index = skipSpaces(from: index + 1)
            } else if characters[index] == "," {
                separatorKind = .comma
                index = skipSpaces(from: index + 1)
            } else if characters[index] == "e", index + 1 < count, characters[index + 1] == " " {
                separatorKind = .conjunction
                index = skipSpaces(from: index + 1)
            }
            guard separatorKind != .none, index < count, characters[index].isNumber else { return nil }

            guard let chapterParse = parseNumber(at: index, maxDigits: 3) else { return nil }
            let afterChapter = chapterParse.end

            // Depois de "," ou de " e " só aceitamos continuação se vier
            // "capítulo:versículo" — caso contrário seria lista de versículos,
            // já tratada em `parseVerseList`.
            let hasVerseSeparator = afterChapter < count && characters[afterChapter] == ":"
            if separatorKind != .semicolon, !hasVerseSeparator { return nil }

            guard BibleBookCatalog.isValidChapter(chapterParse.value, in: book.id) else { return nil }

            var verses: [BibleVerseRange] = []
            var end = afterChapter
            if let verseParse = parseVerseList(at: afterChapter) {
                verses = verseParse.ranges
                end = verseParse.end
            }
            return (BibleReferencePart(chapter: chapterParse.value, verses: verses), end)
        }

        /// Tipo de separador encontrado entre partes da referência.
        private enum Separator { case none, semicolon, comma, conjunction }

        /// Lê a lista de versículos depois de ":" (ou equivalente).
        private func parseVerseList(at start: Int) -> (ranges: [BibleVerseRange], end: Int)? {
            guard start < count else { return nil }
            var index = start

            // Separador entre capítulo e versículo. ":" e "." precisam vir
            // colados ao capítulo; as palavras-chave podem ter espaço antes.
            var consumedSeparator = false
            if characters[index] == ":" {
                index += 1
                consumedSeparator = true
            } else if characters[index] == ".", index + 1 < count, characters[index + 1].isNumber {
                index += 1
                consumedSeparator = true
            } else if let afterKeyword = consumeKeyword(verseKeywords, at: skipSpaces(from: index)) {
                index = afterKeyword
                consumedSeparator = true
            }
            guard consumedSeparator else { return nil }
            index = skipSpaces(from: index)
            guard index < count, characters[index].isNumber else { return nil }

            var ranges: [BibleVerseRange] = []
            guard let first = parseVerseRange(at: index) else { return nil }
            ranges.append(first.range)
            index = first.end

            // Mais versículos: "1, 2, 3", "1 e 2", "4-7, 9".
            while true {
                let separatorStart = index
                var probe = skipSpaces(from: index)
                var matchedSeparator = false
                if probe < count, characters[probe] == "," {
                    probe = skipSpaces(from: probe + 1)
                    matchedSeparator = true
                } else if probe < count, characters[probe] == "e",
                          probe + 1 < count, characters[probe + 1] == " " {
                    probe = skipSpaces(from: probe + 1)
                    matchedSeparator = true
                }
                guard matchedSeparator, probe < count, characters[probe].isNumber else {
                    index = separatorStart
                    break
                }
                // Um número seguido de ":" é novo capítulo, não versículo.
                var lookahead = probe
                while lookahead < count, characters[lookahead].isNumber { lookahead += 1 }
                if lookahead < count, characters[lookahead] == ":" {
                    index = separatorStart
                    break
                }
                guard let next = parseVerseRange(at: probe) else {
                    index = separatorStart
                    break
                }
                ranges.append(next.range)
                index = next.end
            }

            return (ranges, index)
        }

        /// Lê um versículo ou faixa: "16", "16a", "4-7", "16 – 18", "16 a 18".
        private func parseVerseRange(at start: Int) -> (range: BibleVerseRange, end: Int)? {
            guard let first = parseNumber(at: start, maxDigits: 3), first.value >= 1 else { return nil }
            var index = first.end
            var suffix: String? = nil

            // Versículo parcial: "16a", "16b".
            if index < count, ["a", "b", "c"].contains(characters[index]) {
                let afterSuffix = index + 1
                let isWordContinuation = afterSuffix < count && isLetterOrNumber(characters[afterSuffix])
                if !isWordContinuation {
                    suffix = String(characters[index])
                    index = afterSuffix
                }
            }

            var endValue = first.value
            // Faixa: "4-7", "4 – 7", "4 a 7".
            let rangeSeparatorStart = index
            var probe = skipSpaces(from: index)
            var hasRange = false
            if probe < count, ["-", "–", "—"].contains(characters[probe]) {
                probe = skipSpaces(from: probe + 1)
                hasRange = true
            } else if probe < count, characters[probe] == "a",
                      probe + 1 < count, characters[probe + 1] == " " {
                probe = skipSpaces(from: probe + 1)
                hasRange = true
            }
            if hasRange, probe < count, characters[probe].isNumber,
               let second = parseNumber(at: probe, maxDigits: 3) {
                if second.value >= first.value {
                    endValue = second.value
                    index = second.end
                    if index < count, ["a", "b", "c"].contains(characters[index]) {
                        let afterSuffix = index + 1
                        let isWordContinuation = afterSuffix < count && isLetterOrNumber(characters[afterSuffix])
                        if !isWordContinuation { index = afterSuffix }
                    }
                } else {
                    // Faixa invertida ("7-4") não é aceita: mantém só o primeiro.
                    index = rangeSeparatorStart
                }
            } else {
                index = rangeSeparatorStart
            }

            return (BibleVerseRange(start: first.value, end: endValue, suffix: suffix), index)
        }

        /// Lê um número inteiro de até `maxDigits` dígitos.
        private func parseNumber(at start: Int, maxDigits: Int) -> (value: Int, end: Int)? {
            var index = start
            var digits = ""
            while index < count, characters[index].isNumber, digits.count < maxDigits {
                digits.append(characters[index])
                index += 1
            }
            guard !digits.isEmpty, let value = Int(digits) else { return nil }
            return (value, index)
        }

        /// Reconhece o apelido de um livro a partir de uma posição.
        private func matchBookAlias(at start: Int) -> (alias: String, end: Int)? {
            guard start < count else { return nil }
            guard let candidates = aliasTable[characters[start]] else { return nil }
            for candidate in candidates {
                let end = start + candidate.characters.count
                guard end <= count else { continue }
                var matches = true
                for offset in 0..<candidate.characters.count {
                    if characters[start + offset] != candidate.characters[offset] {
                        matches = false
                        break
                    }
                }
                guard matches else { continue }
                // Fronteira à direita: o apelido não pode continuar dentro de
                // outra palavra ("atos" não vale em "atordoar").
                if end < count, isLetterOrNumber(characters[end]) { continue }
                // Apelidos arriscados exigem maiúscula inicial ou ponto depois.
                if riskyAliases.contains(candidate.alias) {
                    let startsUppercase = originalCharacters[start].isUppercase
                    let followedByDot = end < count && characters[end] == "."
                    guard startsUppercase || followedByDot else { continue }
                }
                return (candidate.alias, end)
            }
            return nil
        }

        /// Consome uma palavra-chave ("capítulo", "versículo", "cap.", "v.").
        private func consumeKeyword(_ keywords: [String], at start: Int) -> Int? {
            for keyword in keywords.sorted(by: { $0.count > $1.count }) {
                guard let end = matchWord(keyword, at: start) else { continue }
                var index = end
                if index < count, characters[index] == "." {
                    index += 1
                }
                index = skipSpaces(from: index)
                return index
            }
            return nil
        }

        /// Verifica se a palavra começa exatamente em `start` (com fronteira).
        private func matchWord(_ word: String, at start: Int) -> Int? {
            let wordCharacters = Array(word)
            let end = start + wordCharacters.count
            guard end <= count else { return nil }
            for offset in 0..<wordCharacters.count where characters[start + offset] != wordCharacters[offset] {
                return nil
            }
            if end < count, isLetterOrNumber(characters[end]) { return nil }
            return end
        }

        private func skipSpaces(from start: Int) -> Int {
            var index = start
            while index < count, characters[index] == " " || characters[index] == "\n"
                || characters[index] == "\t" || characters[index] == "\u{00A0}" {
                index += 1
            }
            return index
        }

        private func originalSpelling(from start: Int, to end: Int) -> String {
            guard start < end, end <= originalCharacters.count else { return "" }
            return String(originalCharacters[start..<end])
        }
    }
}
