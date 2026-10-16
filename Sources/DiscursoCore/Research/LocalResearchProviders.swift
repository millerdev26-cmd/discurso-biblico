//
//  LocalResearchProviders.swift
//  DiscursoCore
//
//  Provedores que funcionam sem rede:
//
//   - biblioteca local (materiais indexados do usuário);
//   - pesquisas salvas (favoritos com notas);
//   - referências bíblicas (interpreta "João 3:16" e monta o link oficial);
//   - links oficiais (sempre disponíveis como alternativa documentada).
//
//  Nenhum provedor deste arquivo acessa a rede, e nenhum devolve texto
//  bíblico copiado: as referências geram apenas links para a fonte oficial.
//

import Foundation

// MARK: - Biblioteca local

/// Pesquisa nos materiais importados e indexados.
public struct LocalLibraryResearchProvider: ResearchProvider {

    /// Carregador dos materiais e índices (injetado para manter o provedor
    /// independente do armazenamento).
    public typealias Loader = @Sendable () async -> (items: [LibraryItem], indexes: [UUID: LibraryTextIndex])

    public nonisolated var id: String { ResearchProviderID.localLibrary }
    public nonisolated var displayName: String { "Minha biblioteca" }
    public nonisolated var requiresNetwork: Bool { false }

    private let loader: Loader
    private let maximumItems: Int

    public init(maximumItems: Int = 500, loader: @escaping Loader) {
        self.maximumItems = maximumItems
        self.loader = loader
    }

    public func search(_ query: ResearchQuery) async throws -> [ResearchResult] {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return [] }

        let loaded = await loader()
        let items = Array(loaded.items.filter { $0.isSearchable }.prefix(maximumItems))
        guard !items.isEmpty else { return [] }

        let hits = LibrarySearch.search(
            query: text,
            items: items,
            indexes: loaded.indexes,
            limit: query.limit
        )

        return hits.map { hit in
            ResearchResult(
                providerID: id,
                title: hit.chapterTitle.map { "\(hit.itemTitle) — \($0)" } ?? hit.itemTitle,
                publication: hit.itemTitle,
                snippet: hit.snippet,
                url: nil,
                libraryItemID: hit.itemID,
                locator: hit.locator,
                kind: .localDocument,
                score: 60 + hit.score,
                isAvailableOffline: true
            )
        }
    }
}

// MARK: - Pesquisas salvas

/// Pesquisa nas fontes salvas pelo usuário (favoritos da pesquisa).
public struct SavedResearchProvider: ResearchProvider {

    public typealias Loader = @Sendable () async -> [SavedResearch]

    public nonisolated var id: String { ResearchProviderID.savedResearch }
    public nonisolated var displayName: String { "Pesquisas salvas" }
    public nonisolated var requiresNetwork: Bool { false }

    private let loader: Loader

    public init(loader: @escaping Loader) {
        self.loader = loader
    }

    public func search(_ query: ResearchQuery) async throws -> [ResearchResult] {
        let needle = PortugueseText.folded(query.text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard needle.count >= 2 else { return [] }

        let saved = await loader()
        var results: [ResearchResult] = []
        for item in saved {
            let haystack = [
                item.query,
                item.note,
                item.result.title,
                item.result.publication ?? "",
                item.result.snippet ?? ""
            ]
            guard haystack.contains(where: { PortugueseText.folded($0).contains(needle) }) else { continue }
            var result = item.result.asResearchResult()
            result.score = 55
            results.append(result)
            if results.count >= query.limit { break }
        }
        return results
    }
}

// MARK: - Referências bíblicas

/// Reconhece referências bíblicas na consulta e produz o resultado
/// correspondente com o link para a fonte oficial (sem copiar o texto).
public struct ScriptureResearchProvider: ResearchProvider {

    public nonisolated var id: String { ResearchProviderID.scripture }
    public nonisolated var displayName: String { "Referências bíblicas" }
    public nonisolated var requiresNetwork: Bool { false }

    public init() {}

    public func search(_ query: ResearchQuery) async throws -> [ResearchResult] {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let references: [BibleReference]
        if let detected = query.reference {
            references = [detected]
        } else {
            references = Array(BibleReferenceParser.uniqueReferences(in: text).prefix(5))
        }
        guard !references.isEmpty else { return [] }

        var results: [ResearchResult] = []
        for (index, reference) in references.enumerated() {
            guard reference.isValid() else { continue }
            results.append(ResearchResult(
                providerID: id,
                title: reference.displayText,
                publication: "Bíblia — fonte oficial",
                snippet: "Toque para abrir o capítulo na Biblioteca On-line (fonte oficial).",
                url: reference.officialWebURL(),
                kind: .scripture,
                score: 90 - Double(index),
                isAvailableOffline: false
            ))
        }
        return results
    }
}

// MARK: - Links oficiais

/// Provedor de alternativa: sempre oferece links oficiais de pesquisa.
///
/// Ele nunca falha e nunca depende de rede para ser montado; é o caminho
/// garantido quando a consulta direta não é possível (bloqueio, offline,
/// mudança de marcação da página etc.).
public struct OfficialLinkResearchProvider: ResearchProvider {

    public nonisolated var id: String { ResearchProviderID.jwOrgOfficialLink }
    public nonisolated var displayName: String { "Links oficiais" }
    public nonisolated var requiresNetwork: Bool { false }

    public init() {}

    public func search(_ query: ResearchQuery) async throws -> [ResearchResult] {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [ResearchResult] = []

        if let reference = query.reference ?? BibleReferenceParser.uniqueReferences(in: text).first {
            if let url = reference.officialWebURL() {
                results.append(ResearchResult(
                    providerID: id,
                    title: "Texto bíblico: \(reference.displayText)",
                    publication: "Biblioteca On-line (fonte oficial)",
                    snippet: "O texto bíblico não é armazenado no aplicativo; ele é consultado na fonte oficial.",
                    url: url,
                    kind: .scripture,
                    score: 5,
                    isAvailableOffline: false
                ))
            }
        }

        if !text.isEmpty {
            if let url = officialSearchURL(for: text) {
                results.append(ResearchResult(
                    providerID: id,
                    title: "Pesquisar “\(text)” no site oficial (JW.ORG)",
                    publication: "Pesquisa oficial",
                    snippet: "Abre a pesquisa no site oficial no navegador.",
                    url: url,
                    kind: .article,
                    score: 3,
                    isAvailableOffline: false
                ))
            }
            if let url = WolSearchProvider.searchPageURL(for: text) {
                results.append(ResearchResult(
                    providerID: id,
                    title: "Pesquisar “\(text)” na Biblioteca On-line",
                    publication: "Biblioteca On-line (pesquisa)",
                    snippet: "Consulta direta na página pública de pesquisa.",
                    url: url,
                    kind: .publication,
                    score: 2,
                    isAvailableOffline: false
                ))
            }
        }

        return results
    }

    /// Endereço de pesquisa no site oficial.
    public func officialSearchURL(for text: String, languageCode: String = "pt") -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.jw.org"
        components.path = "/\(languageCode)/busca/"
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }
}
