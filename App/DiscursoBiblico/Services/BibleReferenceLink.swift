//
//  BibleReferenceLink.swift
//  DiscursoBiblico
//
//  Ligações internas para referências bíblicas dentro do texto do discurso.
//
//  Formato (usado nos atributos de link do texto apresentado):
//      discursoref://43/3/16        João 3:16
//      discursoref://43/3/16-17     João 3:16-17
//      discursoref://19/23          Salmos 23 (capítulo inteiro)
//
//  O toque abre o painel do trecho sem perder a posição do discurso.
//

import DiscursoCore
import Foundation

enum BibleReferenceLink {

    static let scheme = "discursoref"

    /// Monta a ligação interna de uma referência.
    static func url(for reference: BibleReference) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = String(reference.bookID.rawValue)

        var path = "/\(reference.primaryChapter)"
        if let first = reference.parts.first, !first.isWholeChapter,
           let range = first.verses.first {
            if range.start == range.end {
                path += "/\(range.start)"
            } else {
                path += "/\(range.start)-\(range.end)"
            }
        }
        components.path = path
        return components.url
    }

    /// Interpreta uma ligação interna. Devolve `nil` para outros endereços.
    static func reference(from url: URL) -> BibleReference? {
        guard url.scheme == scheme,
              let host = url.host,
              let ordinal = Int(host),
              (1...66).contains(ordinal) else {
            return nil
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let chapterText = parts.first, let chapter = Int(chapterText) else { return nil }

        let bookID = BibleBookID(rawValue: ordinal)
        guard let verseText = parts.dropFirst().first else {
            return BibleReference(bookID: bookID, chapter: chapter)
        }

        let pieces = verseText.split(separator: "-").map(String.init)
        guard let start = pieces.first.flatMap(Int.init) else {
            return BibleReference(bookID: bookID, chapter: chapter)
        }
        let end = pieces.dropFirst().first.flatMap(Int.init) ?? start
        return BibleReference(bookID: bookID, chapter: chapter, verseStart: start, verseEnd: end)
    }
}
