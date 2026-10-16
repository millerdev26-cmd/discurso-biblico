//
//  BibleBookCatalog.swift
//  DiscursoCore
//
//  Catálogo dos 66 livros da Bíblia em português do Brasil, com nomes,
//  abreviações comuns, apelidos e quantidade de capítulos.
//
//  Os números (ordinais 1...66) seguem a ordem canônica usada pela
//  Tradução do Novo Mundo e pela Biblioteca On-line (WOL), o que permite
//  montar links oficiais por número do livro:
//    https://wol.jw.org/pt/wol/b/r5/lp-t/nwt/{ordinal}/{capítulo}
//
//  Todos os apelidos são armazenados já normalizados (minúsculos, sem
//  acentos), pois é assim que são comparados com o texto do usuário.
//
//  A quantidade de capítulos é usada para validar referências: "João 25:1"
//  não é uma referência válida porque João tem 21 capítulos.
//

import Foundation

/// Identificador de um livro da Bíblia (ordinal 1...66).
public struct BibleBookID: RawRepresentable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Ordinal 1...66. Retorna `nil` se estiver fora da faixa.
    public init?(ordinal: Int) {
        guard ordinal >= 1, ordinal <= 66 else { return nil }
        self.rawValue = ordinal
    }

    public static let genesis = BibleBookID(rawValue: 1)
    public static let psalms = BibleBookID(rawValue: 19)
    public static let john = BibleBookID(rawValue: 43)
    public static let revelation = BibleBookID(rawValue: 66)

    public static func < (lhs: BibleBookID, rhs: BibleBookID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { "BibleBookID(\(rawValue))" }

    public var info: BibleBookInfo? { BibleBookCatalog.book(ordinal: rawValue) }

    public var name: String { info?.name ?? "Livro \(rawValue)" }
}

/// Metadados de um livro bíblico.
public struct BibleBookInfo: Hashable, Sendable {
    /// Ordinal canônico 1...66.
    public let ordinal: Int
    /// Nome de exibição em pt-BR (como usado na Tradução do Novo Mundo).
    public let name: String
    /// Abreviação recomendada para exibição compacta.
    public let abbreviation: String
    /// Nomes alternativos, sem acentos e em minúsculas, aceitos pelo parser.
    public let aliases: [String]
    /// Quantidade de capítulos do livro.
    public let chapterCount: Int
    /// `true` para o Antigo Testamento (1...39).
    public let isOldTestament: Bool
    /// Prefixo ordinal do nome ("1" em "1 Coríntios"), ou `nil` se o livro não
    /// tem número (ex.: "João", "Salmos").
    ///
    /// É o que permite reconhecer "2 Coríntios 5:1" mesmo que o nome canônico
    /// cadastrado seja apenas "1 Coríntios": o apelido ("corintios") encontra o
    /// *grupo* de livros com o mesmo nome-base e o ordinal escolhe o membro.
    public let ordinalPrefix: Int?
    /// Nome sem o prefixo ordinal, normalizado (ex.: "corintios").
    public let baseFoldedName: String

    public var id: BibleBookID { BibleBookID(rawValue: ordinal) }
}

/// Catálogo estático dos livros da Bíblia.
public enum BibleBookCatalog {

    public static let allBooks: [BibleBookInfo] = buildBooks()

    private static let byOrdinal: [Int: BibleBookInfo] = {
        var map: [Int: BibleBookInfo] = [:]
        for book in allBooks { map[book.ordinal] = book }
        return map
    }()

    /// Índice de apelidos normalizados para os livros correspondentes.
    ///
    /// A maioria dos apelidos aponta para um único livro. Alguns apelidos
    /// curtos são ambíguos por natureza (por exemplo "jo", que pode ser Jó ou
    /// João) e são resolvidos em `BibleReferenceParser` usando o texto
    /// original como desempate.
    private static let aliasIndex: [String: [BibleBookInfo]] = {
        var map: [String: [BibleBookInfo]] = [:]
        for book in allBooks {
            var keys = Set(book.aliases)
            keys.insert(PortugueseText.folded(book.name))
            keys.insert(PortugueseText.folded(book.abbreviation))
            for key in keys where !key.isEmpty {
                map[key, default: []].append(book)
            }
        }
        return map
    }()

    /// Apelidos conhecidos como ambíguos, resolvidos por contexto.
    public static let ambiguousAliases: Set<String> = ["jo", "is", "jd", "na", "os", "am", "lm"]

    /// Todos os apelidos ordenados do mais longo para o mais curto.
    ///
    /// A ordem importa: a expressão regular gerada tenta primeiro os nomes
    /// mais longos para que "cantico de salomao" vença "cantico".
    public static let allAliasesLongestFirst: [String] = {
        aliasIndex.keys.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs < rhs
        }
    }()

    public static func book(ordinal: Int) -> BibleBookInfo? {
        byOrdinal[ordinal]
    }

    public static func books(forAlias alias: String) -> [BibleBookInfo] {
        aliasIndex[alias] ?? []
    }

    public static func chapterCount(of book: BibleBookID) -> Int {
        book.info?.chapterCount ?? 0
    }

    /// Nome de exibição em pt-BR.
    public static func displayName(for book: BibleBookID) -> String {
        book.info?.name ?? "Livro \(book.rawValue)"
    }

    /// Verifica se capítulo e versículo existem no catálogo.
    ///
    /// A quantidade de versículos por capítulo não está incluída no catálogo
    /// (isso só é possível quando há um texto bíblico autorizado carregado).
    /// Portanto validamos o capítulo e exigimos versículo >= 1.
    public static func isValidChapter(_ chapter: Int, in book: BibleBookID) -> Bool {
        guard let info = book.info else { return false }
        return chapter >= 1 && chapter <= info.chapterCount
    }

    /// Índice dos grupos de livros que compartilham o mesmo nome-base.
    ///
    /// Ex.: "corintios" -> [1: 1 Coríntios, 2: 2 Coríntios].
    private static let groupIndex: [String: [Int: BibleBookInfo]] = {
        var map: [String: [Int: BibleBookInfo]] = [:]
        for book in allBooks {
            let key = book.ordinalPrefix ?? 0
            map[book.baseFoldedName, default: [:]][key] = book
        }
        return map
    }()

    /// Desempate explícito para apelidos que são genuinamente ambíguos.
    ///
    /// "jo" normalizado pode ser "Jó" ou "João". O texto original decide: com
    /// acento ("Jó") é o livro de Jó; sem acento ("Jo"/"João") é o Evangelho.
    private static let aliasDisambiguation: [String: (accented: Int, plain: Int)] = [
        "jo": (18, 43)
    ]

    /// Resolve um apelido (e um ordinal opcional) para um livro concreto.
    ///
    /// - Parameters:
    ///   - alias: apelido normalizado encontrado no texto (ex.: "corintios").
    ///   - ordinal: ordinal escrito antes do nome (1, 2, 3), se houver.
    ///   - originalSpelling: o trecho do texto *original* que gerou o apelido,
    ///     usado para distinguir "Jó" de "João".
    public static func resolve(alias: String, ordinal: Int?, originalSpelling: String) -> BibleBookInfo? {
        let candidates = books(forAlias: alias)
        guard !candidates.isEmpty else { return nil }

        if let ordinal {
            for candidate in candidates {
                if let group = groupIndex[candidate.baseFoldedName], let book = group[ordinal] {
                    return book
                }
            }
            return nil
        }

        if candidates.count == 1 { return candidates[0] }

        if let rules = aliasDisambiguation[alias] {
            let spelling = originalSpelling.lowercased()
            let isAccented = spelling.unicodeScalars.contains { scalar in
                ["ó", "ò", "ô", "õ", "ö"].contains(Character(scalar))
            }
            let ordinalValue = isAccented ? rules.accented : rules.plain
            return candidates.first { $0.ordinal == ordinalValue } ?? candidates.first
        }

        if let unnumbered = candidates.first(where: { $0.ordinalPrefix == nil }) {
            return unnumbered
        }
        return candidates.min { $0.ordinal < $1.ordinal }
    }

    private static func buildBooks() -> [BibleBookInfo] {
        func make(
            _ ordinal: Int,
            _ name: String,
            _ abbreviation: String,
            _ chapters: Int,
            _ aliases: [String]
        ) -> BibleBookInfo {
            let foldedName = PortugueseText.folded(name)
            let prefix = Int(String(foldedName.prefix(while: { $0.isNumber })))
            var base = foldedName
            if prefix != nil {
                base = String(foldedName.drop(while: { $0.isNumber || $0 == " " }))
            }
            return BibleBookInfo(
                ordinal: ordinal,
                name: name,
                abbreviation: abbreviation,
                aliases: aliases.map(PortugueseText.folded),
                chapterCount: chapters,
                isOldTestament: ordinal <= 39,
                ordinalPrefix: prefix,
                baseFoldedName: base
            )
        }

        let books: [BibleBookInfo] = [
            make(1, "Gênesis", "Gên.", 50, ["genesis", "gen", "gn", "genes"]),
            make(2, "Êxodo", "Êxo.", 40, ["exodo", "exo", "ex", "exod"]),
            make(3, "Levítico", "Lev.", 27, ["levitico", "lev", "lv"]),
            make(4, "Números", "Núm.", 36, ["numeros", "num", "nm", "nu"]),
            make(5, "Deuteronômio", "Deut.", 34, ["deuteronomio", "deut", "dt"]),
            make(6, "Josué", "Jos.", 24, ["josue", "jos", "js"]),
            make(7, "Juízes", "Juí.", 21, ["juizes", "juiz", "jui", "jz"]),
            make(8, "Rute", "Rute", 4, ["rute", "rt", "ru"]),
            make(9, "1 Samuel", "1 Sam.", 31, ["samuel", "sam", "1sm", "sm"]),
            make(10, "2 Samuel", "2 Sam.", 24, ["2sm"]),
            make(11, "1 Reis", "1 Reis", 22, ["reis", "1rs", "rs"]),
            make(12, "2 Reis", "2 Reis", 25, ["2rs"]),
            make(13, "1 Crônicas", "1 Crô.", 29, ["cronicas", "cron", "1cro", "cro", "cr"]),
            make(14, "2 Crônicas", "2 Crô.", 36, ["2cro"]),
            make(15, "Esdras", "Esd.", 10, ["esdras", "esd", "ed"]),
            make(16, "Neemias", "Nee.", 13, ["neemias", "nee", "ne"]),
            make(17, "Ester", "Est.", 10, ["ester", "est", "et"]),
            make(18, "Jó", "Jó", 42, ["jo", "job"]),
            make(19, "Salmos", "Sal.", 150, ["salmo", "salmos", "sal", "sl", "slm"]),
            make(20, "Provérbios", "Pro.", 31, ["proverbios", "prov", "pro", "pr", "pv"]),
            make(21, "Eclesiastes", "Ecl.", 12, ["eclesiastes", "ecl", "ec"]),
            make(22, "Cântico de Salomão", "Cân.", 8, ["cantico de salomao", "cantico dos canticos", "canticos", "cantares", "can", "ct"]),
            make(23, "Isaías", "Isa.", 66, ["isaias", "isa", "is"]),
            make(24, "Jeremias", "Jer.", 52, ["jeremias", "jer", "jr"]),
            make(25, "Lamentações", "Lam.", 5, ["lamentacoes", "lam", "la", "lm"]),
            make(26, "Ezequiel", "Eze.", 48, ["ezequiel", "eze", "ez"]),
            make(27, "Daniel", "Dan.", 12, ["daniel", "dan", "dn", "da"]),
            make(28, "Oseias", "Ose.", 14, ["oseias", "ose", "os"]),
            make(29, "Joel", "Joel", 3, ["joel", "joe", "jl"]),
            make(30, "Amós", "Amós", 9, ["amos", "am"]),
            make(31, "Obadias", "Oba.", 1, ["obadias", "oba", "ob", "abdias"]),
            make(32, "Jonas", "Jon.", 4, ["jonas", "jon", "jn"]),
            make(33, "Miqueias", "Mique.", 7, ["miqueias", "mique", "miq", "mq", "mi"]),
            make(34, "Naum", "Naum", 3, ["naum", "nau", "na"]),
            make(35, "Habacuque", "Hab.", 3, ["habacuque", "hab", "hc"]),
            make(36, "Sofonias", "Sof.", 3, ["sofonias", "sof", "sf"]),
            make(37, "Ageu", "Ageu", 2, ["ageu", "age", "ag"]),
            make(38, "Zacarias", "Zac.", 14, ["zacarias", "zac", "za"]),
            make(39, "Malaquias", "Mal.", 4, ["malaquias", "mal", "ml"]),
            make(40, "Mateus", "Mat.", 28, ["mateus", "mat", "mt"]),
            make(41, "Marcos", "Mar.", 16, ["marcos", "mar", "mc", "mr"]),
            make(42, "Lucas", "Luc.", 24, ["lucas", "luc", "lc"]),
            make(43, "João", "João", 21, ["joao", "jo", "joa"]),
            make(44, "Atos", "Atos", 28, ["atos", "at", "ato"]),
            make(45, "Romanos", "Rom.", 16, ["romanos", "rom", "ro", "rm"]),
            make(46, "1 Coríntios", "1 Cor.", 16, ["corintios", "cor", "1co", "co"]),
            make(47, "2 Coríntios", "2 Cor.", 13, ["2co"]),
            make(48, "Gálatas", "Gál.", 6, ["galatas", "gal", "ga", "gl"]),
            make(49, "Efésios", "Efé.", 6, ["efesios", "efe", "ef", "efes"]),
            make(50, "Filipenses", "Fil.", 4, ["filipenses", "filip", "fil", "fp", "flp"]),
            make(51, "Colossenses", "Col.", 4, ["colossenses", "col", "cl"]),
            make(52, "1 Tessalonicenses", "1 Tes.", 5, ["tessalonicenses", "tes", "1ts", "ts"]),
            make(53, "2 Tessalonicenses", "2 Tes.", 3, ["2ts"]),
            make(54, "1 Timóteo", "1 Tim.", 6, ["timoteo", "tim", "1tm", "tm"]),
            make(55, "2 Timóteo", "2 Tim.", 4, ["2tm"]),
            make(56, "Tito", "Tito", 3, ["tito", "tit", "tt"]),
            make(57, "Filemom", "Filê.", 1, ["filemom", "filem", "file", "flm", "filemon", "flemom"]),
            make(58, "Hebreus", "Heb.", 13, ["hebreus", "heb", "he", "hb"]),
            make(59, "Tiago", "Tia.", 5, ["tiago", "tia", "tg"]),
            make(60, "1 Pedro", "1 Ped.", 5, ["pedro", "ped", "1pe", "pe"]),
            make(61, "2 Pedro", "2 Ped.", 3, ["2pe"]),
            make(62, "1 João", "1 João", 5, ["1jo"]),
            make(63, "2 João", "2 João", 1, ["2jo"]),
            make(64, "3 João", "3 João", 1, ["3jo"]),
            make(65, "Judas", "Jud.", 1, ["judas", "jud", "jd"]),
            make(66, "Revelação", "Rev.", 22, ["revelacao", "rev", "apocalipse", "apo", "ap"])
        ]

        assert(books.count == 66, "O catálogo deve conter 66 livros")
        return books
    }
}
