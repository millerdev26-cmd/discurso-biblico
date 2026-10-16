//
//  BackupCoordinator.swift
//  DiscursoBiblico
//
//  Exportação e restauração de backup.
//
//  O formato é o mesmo do `BackupService` do núcleo (envelope JSON versão 1),
//  já testado no Linux. Aqui ficam apenas as tarefas de aplicativo:
//  - montar o arquivo em disco para compartilhar;
//  - ler um arquivo escolhido pelo usuário;
//  - aplicar o conteúdo restaurado nos repositórios.
//
//  Restaurar nunca apaga nada por acidente: o modo "mesclar" é a opção
//  sugerida, e o modo "substituir" precisa ser escolhido pelo usuário.
//

import DiscursoCore
import Foundation

/// Exporta e restaura backups.
final class BackupCoordinator: Sendable {

    struct ExportResult: Sendable {
        var fileURL: URL
        var summary: String
        var itemCount: Int
    }

    struct RestoreResult: Sendable {
        var summary: String
        var warnings: [String]
        var importedSpeeches: Int
        var importedLibraryItems: Int
    }

    private let speech: any SpeechRepository
    private let library: any LibraryRepository
    private let research: any ResearchRepository
    private let settings: any SettingsRepository

    init(
        speech: any SpeechRepository,
        library: any LibraryRepository,
        research: any ResearchRepository,
        settings: any SettingsRepository
    ) {
        self.speech = speech
        self.library = library
        self.research = research
        self.settings = settings
    }

    // MARK: Exportação

    /// Monta um arquivo de backup temporário, pronto para o Compartilhar.
    func exportToTemporaryFile(appVersion: String? = nil) async throws -> ExportResult {
        let speeches = try await speech.loadAll()
        let folders = try await speech.folders()
        let items = try await library.loadItems()
        let saved = try await research.savedResearch()
        let history = try await research.searchHistory()
        let appSettings = try? await settings.settings()
        let profiles = try await settings.readingProfiles()

        let data = try BackupService.export(
            speeches: speeches,
            folders: folders,
            libraryItems: items,
            savedResearch: saved,
            searchHistory: history,
            settings: appSettings,
            readingProfiles: profiles,
            appVersion: appVersion
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscursoBiblico", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(BackupService.suggestedFileName())
        try data.write(to: fileURL, options: .atomic)

        let itemCount = speeches.count + items.count + saved.count
        let summary = "\(speeches.count) discurso(s), \(items.count) material(is) da biblioteca e \(saved.count) fonte(s) salva(s)."
        return ExportResult(fileURL: fileURL, summary: summary, itemCount: itemCount)
    }

    // MARK: Restauração

    /// Lê o arquivo e descreve o conteúdo, sem alterar nada.
    func inspect(fileAt url: URL) throws -> BackupContents {
        let data = try readData(from: url)
        switch BackupService.inspect(data: data) {
        case .success(let contents):
            return contents
        case .failure(let error):
            throw error
        }
    }

    /// Aplica o backup escolhido pelo usuário.
    func restore(
        fileAt url: URL,
        strategy: BackupMergeStrategy
    ) async throws -> RestoreResult {
        let data = try readData(from: url)
        let backup = try BackupService.restore(data: data)

        let merged = BackupService.merge(
            backup: backup,
            strategy: strategy,
            currentSpeeches: (try? await speech.loadAll()) ?? [],
            currentFolders: (try? await speech.folders()) ?? [],
            currentLibraryItems: (try? await library.loadItems()) ?? [],
            currentSavedResearch: (try? await research.savedResearch()) ?? []
        )

        for item in merged.speeches { try await speech.save(item) }
        if !merged.folders.isEmpty { try await speech.saveFolders(merged.folders) }
        for item in merged.libraryItems { try await library.save(item) }
        for saved in merged.savedResearch { try await research.save(saved) }
        if let restoredSettings = merged.settings { try await settings.save(restoredSettings) }
        if !merged.readingProfiles.isEmpty { try await settings.save(merged.readingProfiles) }

        var warnings = merged.warnings
        if strategy == .replace {
            warnings.append("O modo \"substituir\" mantém os discursos atuais que também existem no backup; materiais que não estão no backup não são apagados desta vez.")
        }

        let summary = "\(merged.speeches.count) discurso(s), \(merged.libraryItems.count) material(is), \(merged.savedResearch.count) fonte(s) salva(s)."
        return RestoreResult(
            summary: summary,
            warnings: warnings,
            importedSpeeches: merged.speeches.count,
            importedLibraryItems: merged.libraryItems.count
        )
    }

    private func readData(from url: URL) throws -> Data {
        try SecurityScopedAccess.withAccess(to: url) {
            try Data(contentsOf: url, options: [.mappedIfSafe])
        }
    }
}
