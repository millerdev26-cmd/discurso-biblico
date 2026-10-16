//
//  AppEnvironment.swift
//  DiscursoBiblico
//
//  Raiz de composição do aplicativo.
//
//  A interface conversa apenas com os protocolos do `DiscursoCore`; este
//  objeto monta as implementações concretas:
//   - SwiftData como armazenamento principal (discursos, biblioteca,
//     pesquisas e configurações);
//   - arquivos em disco para os materiais importados;
//   - PDFKit para extrair texto de PDF (registrado no extrator do índice);
//   - URLSession para a pesquisa na fonte oficial (com limite de uso);
//   - NWPathMonitor para saber se há conexão.
//
//  Nada aqui é obrigatório para o funcionamento offline: sem rede, o
//  aplicativo continua abrindo tudo o que é local.
//

import DiscursoCore
import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppEnvironment {

    // MARK: Armazenamento

    let container: ModelContainer
    let speechRepository: any SpeechRepository
    let libraryRepository: any LibraryRepository
    let researchRepository: any ResearchRepository
    let settingsRepository: any SettingsRepository
    let files: LibraryFileStore

    // MARK: Serviços do aplicativo

    let network: NetworkMonitor
    let importer: LibraryImportService
    let backup: BackupCoordinator
    let research: ResearchService
    let orientation = OrientationController()
    let screenAwake = ScreenAwakeController()

    // MARK: Estado observado pela interface

    private(set) var settings: AppSettings = .default
    private(set) var readingProfiles: [ReadingProfile] = []
    private(set) var storageWarnings: [String] = []
    private(set) var isLoading = true

    private var didStart = false

    // MARK: Inicialização

    /// Inicializador padrão: banco em disco e pasta de arquivos do aplicativo.
    convenience init() {
        let container = Self.openContainer()
        let files = Self.openFileStore()
        self.init(container: container, files: files)
    }

    /// Inicializador com dependências explícitas (testes e pré-visualizações).
    init(container: ModelContainer, files: LibraryFileStore) {
        self.container = container
        self.files = files

        let speechRepository = SwiftDataSpeechRepository(
            store: SpeechDataStore(modelContainer: container)
        )
        let libraryRepository = SwiftDataLibraryRepository(
            store: LibraryDataStore(modelContainer: container),
            files: files
        )
        let researchRepository = SwiftDataResearchRepository(
            store: ResearchDataStore(modelContainer: container)
        )
        let settingsRepository = SwiftDataSettingsRepository(
            store: SettingsDataStore(modelContainer: container)
        )

        self.speechRepository = speechRepository
        self.libraryRepository = libraryRepository
        self.researchRepository = researchRepository
        self.settingsRepository = settingsRepository

        let network = NetworkMonitor()
        self.network = network

        self.importer = LibraryImportService(
            library: libraryRepository,
            files: files,
            pdfTextExtracting: PDFKitTextExtracting()
        )
        self.backup = BackupCoordinator(
            speech: speechRepository,
            library: libraryRepository,
            research: researchRepository,
            settings: settingsRepository
        )
        self.research = ResearchService.standard(
            policy: .default,
            repository: researchRepository,
            libraryLoader: { [libraryRepository] in
                await AppEnvironment.librarySnapshot(from: libraryRepository)
            },
            savedLoader: { [researchRepository] in
                (try? await researchRepository.savedResearch()) ?? []
            },
            isOnline: { await network.isOnline }
        )
    }

    // MARK: Abertura do armazenamento

    private static func openContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: storeConfiguration())
        } catch {
            // Falha grave (disco cheio, migração impossível): o aplicativo
            // continua abrindo em modo temporário e avisa na tela inicial.
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let fallback = try? ModelContainer(for: schema, configurations: configuration) {
                return fallback
            }
            // Único caso restante: schema inválido (não acontece em produção).
            let empty = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: empty)
        }
    }

    private static func openFileStore() -> LibraryFileStore {
        (try? LibraryFileStore.standard())
            ?? LibraryFileStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
    }

    private static var schema: Schema {
        Schema([
            SpeechRecord.self,
            SpeechFolderRecord.self,
            LibraryItemRecord.self,
            LibraryIndexRecord.self,
            SavedResearchRecord.self,
            SearchHistoryRecord.self,
            CachedResearchRecord.self,
            SettingsRecord.self,
            ReadingProfileRecord.self
        ])
    }

    private static func storeConfiguration() -> ModelConfiguration {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    }

    private static func librarySnapshot(
        from repository: any LibraryRepository
    ) async -> (items: [LibraryItem], indexes: [UUID: LibraryTextIndex]) {
        let items = (try? await repository.loadItems()) ?? []
        var indexes: [UUID: LibraryTextIndex] = [:]
        for item in items where item.indexStatus == .indexed {
            if let index = try? await repository.loadIndex(for: item.id) {
                indexes[item.id] = index
            }
        }
        return (items, indexes)
    }

    // MARK: Ciclo de vida

    /// Carrega configurações, perfis e avisos. Chamado uma vez na abertura.
    func start() async {
        guard !didStart else { return }
        didStart = true
        defer { isLoading = false }

        await loadSettingsAndProfiles()
        await collectStorageWarnings()
    }

    /// Recarrega configurações e perfis (usado após restauração de backup).
    func loadSettingsAndProfiles() async {
        if let loaded = try? await settingsRepository.settings() {
            settings = loaded.sanitized()
            await research.update(policy: settings.researchPolicy)
        }
        if let profiles = try? await settingsRepository.readingProfiles() {
            readingProfiles = profiles
        }
    }

    func saveSettings(_ mutate: (inout AppSettings) -> Void) async {
        var copy = settings
        mutate(&copy)
        settings = copy.sanitized()
        try? await settingsRepository.save(settings)
        await research.update(policy: settings.researchPolicy)
    }

    func saveReadingProfiles(_ profiles: [ReadingProfile]) async {
        readingProfiles = profiles
        try? await settingsRepository.save(profiles)
    }

    /// Junta avisos de armazenamento em uma única lista para a interface.
    func collectStorageWarnings() async {
        var messages = settings.pendingStorageWarnings
        if let speech = speechRepository as? SwiftDataSpeechRepository {
            messages.append(contentsOf: await speech.takeWarnings().map(\.message))
        }
        storageWarnings = messages
    }

    func acknowledgeStorageWarnings() async {
        storageWarnings = []
        await saveSettings { $0.pendingStorageWarnings = [] }
    }

    // MARK: Apoio à interface

    /// Registra uma etiqueta usada recentemente (sugestões no editor).
    func noteRecentTag(_ tag: String) async {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await saveSettings { settings in
            var list = settings.recentTags.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
            list.insert(trimmed, at: 0)
            settings.recentTags = Array(list.prefix(12))
        }
    }

    func noteRecentOccasion(_ occasion: String) async {
        let trimmed = occasion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await saveSettings { settings in
            var list = settings.recentOccasions.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
            list.insert(trimmed, at: 0)
            settings.recentOccasions = Array(list.prefix(8))
        }
    }

    /// Cria o coordenador de salvamento automático para um discurso.
    func makeAutosaveCoordinator(debounce: Double = 2.5) -> AutosaveCoordinator {
        AutosaveCoordinator(debounceSeconds: debounce, repository: speechRepository)
    }

    /// Preferências padrão do modo de apresentação (último perfil usado).
    var defaultPresentationPreferences: PresentationPreferences {
        if let id = settings.lastUsedReadingProfileID,
           let profile = readingProfiles.first(where: { $0.id == id }) {
            return profile.preferences
        }
        return settings.defaultPresentation
    }

    // MARK: Pré-visualizações e testes

    /// Ambiente em memória (nunca grava em disco), para pré-visualizações.
    static func preview() -> AppEnvironment {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: configuration)
        let files = LibraryFileStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
        let environment = AppEnvironment(container: container, files: files)
        environment.readingProfiles = ReadingProfile.builtInProfiles
        environment.isLoading = false
        return environment
    }
}
