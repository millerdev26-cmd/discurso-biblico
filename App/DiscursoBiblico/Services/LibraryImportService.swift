//
//  LibraryImportService.swift
//  DiscursoBiblico
//
//  Importação de materiais para a biblioteca pessoal.
//
//  Fluxo de cada arquivo:
//   1. lê os bytes (respeitando o acesso com escopo de segurança);
//   2. `ImportService.prepare` do núcleo faz a triagem: extensão, tamanho,
//      bytes iniciais, DRM, hash e duplicidade — **nada é gravado antes de
//      passar por essa validação**;
//   3. copia o arquivo para a pasta do aplicativo;
//   4. indexa o texto (EPUB/HTML/Markdown/texto; PDF via PDFKit);
//   5. grava o material com a situação da indexação.
//
//  Arquivos inválidos, duplicados ou protegidos geram mensagens claras, sem
//  interromper a importação dos demais.
//

import DiscursoCore
import Foundation

/// Resultado de uma importação em lote, pronto para exibição.
struct LibraryImportReport: Sendable {

    struct Issue: Sendable, Identifiable {
        var id = UUID()
        var fileName: String
        var message: String
        var recovery: String?
    }

    var imported: [LibraryItem] = []
    var duplicates: [Issue] = []
    var failures: [Issue] = []
    var warnings: [String] = []

    var isEmpty: Bool { imported.isEmpty && duplicates.isEmpty && failures.isEmpty }

    var summaryMessage: String {
        var parts: [String] = []
        if !imported.isEmpty { parts.append("\(imported.count) importado(s)") }
        if !duplicates.isEmpty { parts.append("\(duplicates.count) já existente(s)") }
        if !failures.isEmpty { parts.append("\(failures.count) com problema") }
        return parts.joined(separator: " · ")
    }
}

/// Importa arquivos escolhidos pelo usuário.
final class LibraryImportService: Sendable {

    private let library: any LibraryRepository
    private let files: LibraryFileStore
    private let pdfTextExtracting: any PDFTextExtracting

    init(
        library: any LibraryRepository,
        files: LibraryFileStore,
        pdfTextExtracting: any PDFTextExtracting = PDFKitUnavailableExtractor()
    ) {
        self.library = library
        self.files = files
        self.pdfTextExtracting = pdfTextExtracting
    }

    /// Importa uma lista de arquivos (em ordem), sem parar nos erros.
    func importFiles(
        at urls: [URL],
        policy: ImportPolicy = .default
    ) async -> LibraryImportReport {
        var report = LibraryImportReport()
        var existing = (try? await library.loadItems()) ?? []

        for url in urls {
            let fileName = url.lastPathComponent
            let data: Data
            do {
                data = try readData(from: url)
            } catch {
                report.failures.append(.init(
                    fileName: fileName,
                    message: "Não foi possível ler o arquivo.",
                    recovery: error.localizedDescription
                ))
                continue
            }

            let prepared: PreparedImport
            do {
                prepared = try ImportService.prepare(
                    data: data,
                    originalFileName: fileName,
                    sourceURL: nil,
                    existingItems: existing,
                    policy: policy
                )
            } catch let error as ImportError {
                report.failures.append(.init(
                    fileName: fileName,
                    message: error.errorDescription ?? "Arquivo não aceito.",
                    recovery: error.recoverySuggestion
                ))
                continue
            } catch {
                report.failures.append(.init(
                    fileName: fileName,
                    message: "Falha ao preparar a importação.",
                    recovery: error.localizedDescription
                ))
                continue
            }

            if let duplicateOf = prepared.duplicateOf {
                report.duplicates.append(.init(
                    fileName: fileName,
                    message: "Este conteúdo já está na biblioteca.",
                    recovery: "Material existente: \(existing.first { $0.id == duplicateOf }?.displayTitle ?? "sem título")."
                ))
                continue
            }

            var item = prepared.item

            do {
                try files.store(data: data, itemID: item.id, fileExtension: item.fileExtension)
            } catch {
                report.failures.append(.init(
                    fileName: fileName,
                    message: "Não foi possível guardar o arquivo no aplicativo.",
                    recovery: error.localizedDescription
                ))
                continue
            }

            // Indexação para pesquisa local (offline).
            do {
                let indexed = try LibraryIndexer.buildIndex(
                    for: item,
                    data: data,
                    pdfTextExtracting: pdfTextExtracting
                )
                item.indexStatus = .indexed
                item.indexFailureReason = nil
                item.unitCount = indexed.unitCount
                if item.author == nil { item.author = indexed.author }
                try await library.saveIndex(indexed.index, for: item.id)
                report.warnings.append(contentsOf: indexed.warnings.map { "\(fileName): \($0)" })
            } catch let error as LibraryIndexingError {
                item.indexStatus = .failed
                item.indexFailureReason = error.errorDescription
                report.warnings.append("\(fileName): \(error.errorDescription ?? "Não foi possível indexar.") O material continua disponível para leitura.")
            } catch {
                item.indexStatus = .failed
                item.indexFailureReason = error.localizedDescription
                report.warnings.append("\(fileName): falha ao indexar (\(error.localizedDescription)).")
            }

            do {
                try await library.save(item)
            } catch {
                report.failures.append(.init(
                    fileName: fileName,
                    message: "Não foi possível registrar o material.",
                    recovery: error.localizedDescription
                ))
                continue
            }

            for warning in prepared.warnings {
                report.warnings.append("\(fileName): \(warning.message)")
            }
            existing.append(item)
            report.imported.append(item)
        }

        return report
    }

    /// Reindexa um material já importado (por exemplo, depois de corrigir um
    /// PDF digitalizado ou trocar a implementação de extração).
    func reindex(_ item: LibraryItem) async -> Result<LibraryItem, ImportError> {
        guard let fileURL = await library.fileURL(for: item) else {
            return .failure(.unreadableFile(reason: "o arquivo do material não está mais disponível no armazenamento do aplicativo"))
        }
        var updated = item
        do {
            let data = try readData(from: fileURL)
            let indexed = try LibraryIndexer.buildIndex(
                for: item,
                data: data,
                pdfTextExtracting: pdfTextExtracting
            )
            updated.indexStatus = .indexed
            updated.indexFailureReason = nil
            updated.unitCount = indexed.unitCount
            try await library.saveIndex(indexed.index, for: item.id)
        } catch let error as LibraryIndexingError {
            updated.indexStatus = .failed
            updated.indexFailureReason = error.errorDescription
        } catch {
            updated.indexStatus = .failed
            updated.indexFailureReason = error.localizedDescription
        }
        try? await library.save(updated)
        return .success(updated)
    }

    private func readData(from url: URL) throws -> Data {
        try SecurityScopedAccess.withAccess(to: url) {
            try Data(contentsOf: url, options: [.mappedIfSafe])
        }
    }
}
