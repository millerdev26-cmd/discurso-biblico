//
//  PayloadCoding.swift
//  DiscursoBiblico
//
//  Codificação dos modelos do núcleo gravados nos registros do SwiftData.
//
//  O aplicativo guarda cada modelo como o mesmo JSON que a implementação em
//  arquivos do pacote `DiscursoCore` usa (datas em ISO 8601). Assim:
//   - um discurso exportado no backup e restaurado volta idêntico;
//   - o armazenamento em arquivo do pacote continua sendo uma alternativa
//     válida (útil para testes, recuperação e diagnóstico no Mac);
//   - os registros do SwiftData carregam apenas colunas de índice (título,
//     datas, contagens) além do conteúdo.
//

import DiscursoCore
import Foundation

enum PayloadCoding {

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Codifica um modelo do núcleo. Erros são impossíveis na prática para os
    /// tipos usados aqui (todos Codable sem valores não representáveis);
    /// devolve `Data()` para nunca derrubar o aplicativo.
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
