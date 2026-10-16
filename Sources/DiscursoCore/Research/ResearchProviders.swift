//
//  ResearchProviders.swift
//  DiscursoCore
//
//  Contratos da área de pesquisa.
//
//  Cada provedor é isolado: tem um identificador, sabe se depende de rede e
//  devolve resultados no modelo comum (`ResearchResult`). Trocar, desligar ou
//  adicionar um provedor não afeta os demais nem a interface.
//
//  Regras de acesso aplicadas aos provedores de rede:
//   - identificação clara no User-Agent;
//   - um pedido por vez, com intervalo mínimo entre pedidos;
//   - sem contorno de CAPTCHA/desafios: nessas situações o provedor **para**
//     e devolve um erro explicativo;
//   - o link para a busca oficial continua disponível como alternativa.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Erros comuns aos provedores de pesquisa.
public enum ResearchProviderError: LocalizedError, Equatable {
    /// Sem conexão (o provedor depende de rede).
    case offline
    /// O servidor pediu verificação (CAPTCHA) ou recusou o acesso.
    case accessBlocked(String)
    /// Limite de requisições atingido (HTTP 429).
    case rateLimited(retryAfter: Double?)
    /// Resposta inesperada do servidor.
    case badResponse(String)
    /// Resposta HTTP com erro.
    case httpStatus(Int)
    /// Provedor desativado pelas configurações.
    case notConfigured(String)
    /// Cancelado pelo usuário.
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .offline:
            return "Sem conexão com a internet."
        case .accessBlocked(let reason):
            return "O acesso à fonte foi bloqueado (\(reason)). Use os links oficiais para continuar."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Muitas consultas seguidas. Tente novamente em \(Int(retryAfter.rounded())) s."
            }
            return "Muitas consultas seguidas. Aguarde um pouco antes de tentar de novo."
        case .badResponse(let reason):
            return "A resposta da fonte não pôde ser interpretada (\(reason))."
        case .httpStatus(let code):
            return "A fonte respondeu com um erro (\(code))."
        case .notConfigured(let reason):
            return reason
        case .cancelled:
            return "Pesquisa cancelada."
        }
    }
}

/// Consulta de pesquisa.
public struct ResearchQuery: Hashable, Sendable {
    /// Texto digitado pelo usuário.
    public var text: String
    /// Referência bíblica reconhecida no texto, quando houver.
    public var reference: BibleReference?
    /// Limite de resultados.
    public var limit: Int

    public init(text: String, reference: BibleReference? = nil, limit: Int = 40) {
        self.text = text
        self.reference = reference
        self.limit = limit
    }

    /// Cria a consulta já reconhecendo referências no texto.
    public static func detectingReference(in text: String, limit: Int = 40) -> ResearchQuery {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = trimmed.isEmpty ? nil : BibleReferenceParser.uniqueReferences(in: trimmed).first
        return ResearchQuery(text: trimmed, reference: reference, limit: limit)
    }
}

/// Contrato de um provedor de pesquisa.
public protocol ResearchProvider: Sendable {
    /// Identificador estável (ver `ResearchProviderID`).
    var id: String { get }
    /// Nome exibido na interface.
    var displayName: String { get }
    /// `true` quando depende de rede (usado no modo offline).
    var requiresNetwork: Bool { get }
    /// Executa a pesquisa.
    func search(_ query: ResearchQuery) async throws -> [ResearchResult]
}

// MARK: - Camada HTTP

/// Requisição HTTP mínima (não depende de URLSession, para ser testável).
public struct HTTPFetchRequest: Hashable, Sendable {
    public var url: URL
    public var timeout: TimeInterval
    public var userAgent: String
    public var acceptLanguage: String?

    public init(
        url: URL,
        timeout: TimeInterval = 20,
        userAgent: String = AppSettings.defaultUserAgent,
        acceptLanguage: String? = "pt-BR,pt;q=0.9"
    ) {
        self.url = url
        self.timeout = timeout
        self.userAgent = userAgent
        self.acceptLanguage = acceptLanguage
    }
}

/// Resposta HTTP mínima.
public struct HTTPFetchResponse: Hashable, Sendable {
    public var statusCode: Int
    public var data: Data
    public var url: URL?

    public init(statusCode: Int, data: Data, url: URL? = nil) {
        self.statusCode = statusCode
        self.data = data
        self.url = url
    }
}

/// Executor de requisições HTTP.
public protocol HTTPFetching: Sendable {
    func fetch(_ request: HTTPFetchRequest) async throws -> HTTPFetchResponse
}

/// Executor baseado em URLSession (iOS e Linux).
///
/// A implementação é deliberadamente simples: um GET por vez, sem cookies
/// persistentes, sem redirecionamentos para domínios inesperados e com
/// identificação no User-Agent.
public struct URLSessionHTTPFetcher: HTTPFetching {

    public init() {}

    public func fetch(_ request: HTTPFetchRequest) async throws -> HTTPFetchResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = request.timeout
        urlRequest.setValue(request.userAgent, forHTTPHeaderField: "User-Agent")
        if let language = request.acceptLanguage {
            urlRequest.setValue(language, forHTTPHeaderField: "Accept-Language")
        }
        urlRequest.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            return HTTPFetchResponse(statusCode: statusCode, data: data, url: response.url)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost:
                throw ResearchProviderError.offline
            case .timedOut:
                throw ResearchProviderError.badResponse("tempo esgotado")
            case .cancelled:
                throw ResearchProviderError.cancelled
            default:
                throw ResearchProviderError.badResponse(error.localizedDescription)
            }
        } catch let error as ResearchProviderError {
            throw error
        } catch {
            throw ResearchProviderError.badResponse(error.localizedDescription)
        }
    }
}
