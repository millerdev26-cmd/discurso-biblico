//
//  DocumentStore.swift
//  DiscursoCore
//
//  Persistência local em disco, à prova de falhas.
//
//  Garantias oferecidas:
//
//   1. **Escrita atômica**: grava em `<arquivo>.tmp`, sincroniza e só então
//      substitui o arquivo final. Um desligamento no meio da gravação nunca
//      deixa o arquivo final truncado.
//   2. **Cópia de segurança**: antes de substituir, o conteúdo anterior vai
//      para `<arquivo>.bak` (uma geração).
//   3. **Recuperação**: ao ler, se o arquivo principal estiver corrompido,
//      tenta automaticamente a cópia `.bak` e informa qual foi usada.
//   4. **Nunca apagar dados por falha de rede**: nada aqui depende de rede.
//
//  O mesmo armazenamento é usado pelos testes aqui no Linux e no aplicativo
//  iOS (que também mantém um índice em SwiftData).
//

import Foundation

/// Erros de persistência com mensagens prontas para o usuário.
public enum DocumentStoreError: LocalizedError, Equatable {
    case directoryUnavailable(String)
    case notFound(String)
    case corrupted(file: String, reason: String)
    case writeFailed(file: String, reason: String)
    case decodingFailed(file: String, reason: String)
    case invalidBackup(reason: String)

    public var errorDescription: String? {
        switch self {
        case .directoryUnavailable(let path):
            return "Não foi possível acessar a pasta de dados (\(path))."
        case .notFound(let file):
            return "O arquivo \(file) não foi encontrado."
        case .corrupted(let file, let reason):
            return "O arquivo \(file) está corrompido: \(reason)."
        case .writeFailed(let file, let reason):
            return "Falha ao gravar \(file): \(reason)."
        case .decodingFailed(let file, let reason):
            return "Não foi possível ler \(file): \(reason)."
        case .invalidBackup(let reason):
            return "Backup inválido: \(reason)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .corrupted:
            return "Uma cópia de segurança foi usada automaticamente quando possível. Você também pode restaurar um backup em Configurações."
        case .writeFailed:
            return "Verifique o espaço disponível no dispositivo e tente novamente."
        case .invalidBackup:
            return "Escolha um arquivo de backup gerado pelo próprio aplicativo."
        default:
            return nil
        }
    }
}

/// Resultado de leitura com informação sobre recuperação.
public struct DocumentLoadResult<Value> {
    public let value: Value
    /// `true` quando o arquivo principal estava corrompido e a cópia
    /// de segurança foi usada.
    public let recoveredFromBackup: Bool
    /// Aviso a exibir ao usuário, quando houve recuperação.
    public let warning: String?
}

/// Armazenamento de documentos JSON com escrita atômica.
public actor DocumentStore {

    /// Diretório raiz de todos os dados do aplicativo.
    public nonisolated let baseDirectory: URL

    private nonisolated let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Caminhos

    /// Caminho absoluto de um arquivo relativo à raiz.
    public nonisolated func url(for relativePath: String) -> URL {
        baseDirectory.appendingPathComponent(relativePath)
    }

    /// Garante que a pasta informada exista.
    @discardableResult
    public func ensureDirectory(_ relativePath: String) throws -> URL {
        let directory = url(for: relativePath)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            throw DocumentStoreError.directoryUnavailable(directory.path)
        }
    }

    /// Cria a estrutura de pastas padrão do aplicativo.
    public func prepareDefaultLayout() throws {
        for path in DocumentPaths.allDirectories {
            try ensureDirectory(path)
        }
    }

    // MARK: - Leitura e escrita

    /// Grava um valor codificável de forma atômica.
    public func save<T: Encodable>(_ value: T, to relativePath: String) throws {
        let destination = url(for: relativePath)
        let directory = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw DocumentStoreError.directoryUnavailable(directory.path)
        }

        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw DocumentStoreError.writeFailed(file: relativePath, reason: error.localizedDescription)
        }

        let temporary = destination.appendingPathExtension("tmp")
        do {
            try data.write(to: temporary, options: [.atomic])
        } catch {
            throw DocumentStoreError.writeFailed(file: relativePath, reason: error.localizedDescription)
        }

        // Guarda a versão anterior como cópia de segurança.
        if fileManager.fileExists(atPath: destination.path) {
            let backup = destination.appendingPathExtension("bak")
            try? fileManager.removeItem(at: backup)
            try? fileManager.copyItem(at: destination, to: backup)
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw DocumentStoreError.writeFailed(file: relativePath, reason: error.localizedDescription)
        }
    }

    /// Lê um valor, com recuperação automática a partir da cópia de segurança.
    public func load<T: Decodable>(
        _ type: T.Type,
        from relativePath: String
    ) throws -> DocumentLoadResult<T>? {
        let destination = url(for: relativePath)
        guard fileManager.fileExists(atPath: destination.path) else {
            // Talvez exista apenas a cópia de segurança (queda durante troca).
            let backup = destination.appendingPathExtension("bak")
            guard fileManager.fileExists(atPath: backup.path) else { return nil }
            let value = try decode(T.self, at: backup, relativePath: relativePath)
            return DocumentLoadResult(
                value: value,
                recoveredFromBackup: true,
                warning: "O arquivo \(relativePath) estava ausente; a cópia de segurança foi usada."
            )
        }

        do {
            let value = try decode(T.self, at: destination, relativePath: relativePath)
            return DocumentLoadResult(value: value, recoveredFromBackup: false, warning: nil)
        } catch {
            let backup = destination.appendingPathExtension("bak")
            guard fileManager.fileExists(atPath: backup.path),
                  let recovered = try? decode(T.self, at: backup, relativePath: relativePath)
            else { throw error }
            return DocumentLoadResult(
                value: recovered,
                recoveredFromBackup: true,
                warning: "O arquivo \(relativePath) estava corrompido; a cópia de segurança foi restaurada."
            )
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, at url: URL, relativePath: String) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentStoreError.corrupted(file: relativePath, reason: error.localizedDescription)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw DocumentStoreError.corrupted(file: relativePath, reason: error.localizedDescription)
        }
    }

    /// Lê dados brutos (usado em validação de backup).
    public func loadData(from relativePath: String) throws -> Data? {
        let destination = url(for: relativePath)
        guard fileManager.fileExists(atPath: destination.path) else { return nil }
        return try Data(contentsOf: destination)
    }

    /// Grava dados brutos de forma atômica (restauração de backup).
    public func saveData(_ data: Data, to relativePath: String) throws {
        let destination = url(for: relativePath)
        let directory = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw DocumentStoreError.directoryUnavailable(directory.path)
        }
        let temporary = destination.appendingPathExtension("tmp")
        do {
            try data.write(to: temporary, options: [.atomic])
        } catch {
            throw DocumentStoreError.writeFailed(file: relativePath, reason: error.localizedDescription)
        }
        if fileManager.fileExists(atPath: destination.path) {
            let backup = destination.appendingPathExtension("bak")
            try? fileManager.removeItem(at: backup)
            try? fileManager.copyItem(at: destination, to: backup)
        }
        do {
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw DocumentStoreError.writeFailed(file: relativePath, reason: error.localizedDescription)
        }
    }

    public func delete(relativePath: String) throws {
        let destination = url(for: relativePath)
        guard fileManager.fileExists(atPath: destination.path) else { return }
        do {
            try fileManager.removeItem(at: destination)
            try? fileManager.removeItem(at: destination.appendingPathExtension("bak"))
        } catch {
            throw DocumentStoreError.writeFailed(file: relativePath, reason: error.localizedDescription)
        }
    }

    /// Lista os nomes de arquivo de uma pasta, sem extensão.
    public nonisolated func listFileNames(in relativePath: String, extension fileExtension: String) -> [String] {
        let directory = url(for: relativePath)
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        return contents
            .filter { $0.hasSuffix(".\(fileExtension)") }
            .map { String($0.dropLast(fileExtension.count + 1)) }
            .sorted()
    }

    /// `true` quando existe o arquivo informado.
    public nonisolated func exists(relativePath: String) -> Bool {
        fileManager.fileExists(atPath: url(for: relativePath).path)
    }

    /// Tamanho em bytes de um arquivo (0 se não existir).
    public nonisolated func fileSize(relativePath: String) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url(for: relativePath).path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Cria (ou reutiliza) um subdiretório dentro da raiz e devolve a URL.
    public func makeScratchDirectory(named name: String) throws -> URL {
        let directory = url(for: "tmp/\(name)")
        try ensureDirectory("tmp/\(name)")
        return directory
    }
}

/// Caminhos padronizados usados pelo aplicativo.
public enum DocumentPaths {
    public static let speeches = "speeches"
    public static let folders = "folders"
    public static let libraryItems = "library/items"
    public static let libraryFiles = "library/files"
    public static let libraryIndexes = "library/indexes"
    public static let research = "research"
    public static let researchCache = "research/cache"
    public static let settings = "settings"
    public static let bibles = "bible"
    public static let temporary = "tmp"

    public static let allDirectories = [
        speeches, folders, libraryItems, libraryFiles, libraryIndexes,
        research, researchCache, settings, bibles, temporary
    ]

    public static let speechFileName = "settings/speech-index.json"
    public static let folderFileName = "folders/folders.json"
    public static let appSettingsFileName = "settings/app.json"
    public static let readingProfilesFileName = "settings/reading-profiles.json"
    public static let savedResearchFileName = "research/saved.json"
    public static let searchHistoryFileName = "research/history.json"
    public static let bibleSourcesFileName = "bible/sources.json"
}
