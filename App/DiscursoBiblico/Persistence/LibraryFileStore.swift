//
//  LibraryFileStore.swift
//  DiscursoBiblico
//
//  Guarda os arquivos dos materiais da biblioteca em disco
//  (`<Suporte do app>/Library/files/<id>.<ext>`), fora dos registros do
//  SwiftData — do mesmo modo que a implementação em arquivos do núcleo faz.
//

import DiscursoCore
import Foundation

/// Armazenamento dos arquivos originais da biblioteca.
struct LibraryFileStore: Sendable {

    let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// Cria a pasta padrão dentro de "Application Support".
    static func standard(fileManager: FileManager = .default) throws -> LibraryFileStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("DiscursoBiblico", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("files", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return LibraryFileStore(rootDirectory: directory)
    }

    func fileURL(itemID: UUID, fileExtension: String) -> URL {
        let ext = fileExtension.lowercased()
        let name = ext.isEmpty ? itemID.uuidString : "\(itemID.uuidString).\(ext)"
        return rootDirectory.appendingPathComponent(name)
    }

    func fileURL(for item: LibraryItem) -> URL {
        fileURL(itemID: item.id, fileExtension: item.fileExtension)
    }

    func fileExists(for item: LibraryItem) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: item).path)
    }

    /// Copia o arquivo para a pasta do aplicativo, substituindo uma versão
    /// anterior do mesmo identificador (reindexação).
    @discardableResult
    func store(data: Data, itemID: UUID, fileExtension: String) throws -> String {
        let destination = fileURL(itemID: itemID, fileExtension: fileExtension)
        try data.write(to: destination, options: .atomic)
        return destination.lastPathComponent(withExtension: true)
    }

    /// Copia um arquivo escolhido pelo usuário (respeitando o acesso com
    /// escopo de segurança do `fileImporter`).
    @discardableResult
    func store(copying sourceURL: URL, itemID: UUID, fileExtension: String) throws -> String {
        try SecurityScopedAccess.withAccess(to: sourceURL) {
            let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            return try store(data: data, itemID: itemID, fileExtension: fileExtension)
        }
    }

    func removeFile(for item: LibraryItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
    }
}

private extension URL {
    /// Nome do arquivo incluindo a extensão (o `lastPathComponent` do
    /// Foundation já faz isso; este auxiliar existe para deixar claro que
    /// queremos o nome completo, e para centralizar um eventual ajuste).
    func lastPathComponent(withExtension: Bool) -> String {
        lastPathComponent
    }
}
