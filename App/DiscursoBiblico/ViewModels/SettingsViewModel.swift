//
//  SettingsViewModel.swift
//  DiscursoBiblico
//
//  Configurações: preferências gerais, perfis de leitura, regras de pesquisa,
//  privacidade e backup (exportar/restaurar).
//

import DiscursoCore
import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {

    var settings: AppSettings = .default
    private(set) var profiles: [ReadingProfile] = []

    private(set) var backupFileURL: URL?
    private(set) var backupSummary: String?
    private(set) var restorePreview: String?
    private(set) var lastMessage: String?
    private(set) var errorMessage: String?
    private(set) var isWorking = false

    var restoreStrategy: BackupMergeStrategy = .merge

    private let settingsRepository: any SettingsRepository
    private let backup: BackupCoordinator
    private let researchRepository: any ResearchRepository
    private let researchService: ResearchService

    init(
        settingsRepository: any SettingsRepository,
        backup: BackupCoordinator,
        researchRepository: any ResearchRepository,
        researchService: ResearchService
    ) {
        self.settingsRepository = settingsRepository
        self.backup = backup
        self.researchRepository = researchRepository
        self.researchService = researchService
    }

    func load() async {
        if let loaded = try? await settingsRepository.settings() {
            settings = loaded.sanitized()
        }
        if let profiles = try? await settingsRepository.readingProfiles() {
            self.profiles = profiles
        }
    }

    /// Grava as configurações e atualiza a política de pesquisa em vigor.
    func persist() async {
        let sanitized = settings.sanitized()
        settings = sanitized
        do {
            try await settingsRepository.save(sanitized)
            await researchService.update(policy: sanitized.researchPolicy)
        } catch {
            errorMessage = "Não foi possível gravar as configurações (\(error.localizedDescription))."
        }
    }

    func persistProfiles() async {
        try? await settingsRepository.save(profiles)
    }

    // MARK: Provedores de pesquisa

    var availableProviders: [(id: String, displayName: String, requiresNetwork: Bool)] {
        get async { await researchService.availableProviders() }
    }

    func isProviderEnabled(_ id: String) -> Bool {
        settings.enabledResearchProviderIDs.contains(id)
    }

    func setProvider(_ id: String, enabled: Bool) async {
        var ids = settings.enabledResearchProviderIDs
        if enabled {
            if !ids.contains(id) { ids.append(id) }
        } else {
            ids.removeAll { $0 == id }
        }
        settings.enabledResearchProviderIDs = ids
        await persist()
    }

    // MARK: Backup

    func exportBackup() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await backup.exportToTemporaryFile(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            )
            backupFileURL = result.fileURL
            backupSummary = result.summary
            lastMessage = "Backup pronto para compartilhar: \(result.summary)"
            errorMessage = nil
        } catch let error as BackupError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível exportar o backup (\(error.localizedDescription))."
        }
    }

    /// Lê o arquivo e descreve o conteúdo antes de restaurar.
    func inspectBackup(fileURL: URL) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let contents = try backup.inspect(fileAt: fileURL)
            restorePreview = "Backup de \(Self.dateText(contents.exportedAt)): \(contents.speeches.count) discurso(s), \(contents.libraryItems.count) material(is), \(contents.savedResearch.count) fonte(s) salva(s)."
            errorMessage = nil
        } catch let error as BackupError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível ler o backup (\(error.localizedDescription))."
        }
    }

    func restoreBackup(fileURL: URL) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await backup.restore(fileAt: fileURL, strategy: restoreStrategy)
            lastMessage = "Backup aplicado: \(result.summary)"
            if !result.warnings.isEmpty {
                lastMessage = (lastMessage ?? "") + " Avisos: " + result.warnings.joined(separator: " ")
            }
            errorMessage = nil
            await load()
        } catch let error as BackupError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível restaurar (\(error.localizedDescription))."
        }
    }

    // MARK: Dados de pesquisa

    func clearSearchHistory() async {
        try? await researchRepository.clearSearchHistory()
        lastMessage = "Histórico de pesquisas apagado."
    }

    func clearResearchCache() async {
        try? await researchRepository.clearCache()
        lastMessage = "Resultados guardados da pesquisa foram apagados."
    }

    // MARK: Apoio

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
