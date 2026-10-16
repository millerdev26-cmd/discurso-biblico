//
//  BackupService.swift
//  DiscursoCore
//
//  Cópia de segurança completa (exportar e restaurar).
//
//  O arquivo de backup é um JSON versionado e legível:
//
//    { "formatVersion": 1, "exportedAt": "...", "speeches": [...], ... }
//
//  Regras de segurança na restauração:
//   1. o arquivo precisa ser um backup deste aplicativo (assinatura de formato);
//   2. backups de versões **mais novas** são recusados (não inventamos dados);
//   3. registros individuais com esquema mais novo são restaurados, mas
//      geram aviso (campos desconhecidos podem ser perdidos ao regravar);
//   4. nada é apagado antes de o arquivo inteiro ser validado.
//

import Foundation

/// Erros de backup/restauração.
public enum BackupError: LocalizedError, Equatable {
    case unreadable(reason: String)
    case notABackup
    case unsupportedVersion(Int)
    case emptyBackup

    public var errorDescription: String? {
        switch self {
        case .unreadable(let reason):
            return "Não foi possível ler o backup: \(reason)."
        case .notABackup:
            return "O arquivo escolhido não é um backup do Discurso Bíblico."
        case .unsupportedVersion(let version):
            return "Este backup foi criado por uma versão mais nova do aplicativo (formato \(version))."
        case .emptyBackup:
            return "O backup não contém discursos nem configurações."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unsupportedVersion:
            return "Atualize o aplicativo para restaurar este backup."
        case .notABackup, .unreadable:
            return "Escolha um arquivo gerado em Configurações › Backup › Exportar."
        case .emptyBackup:
            return "Gere um novo backup a partir do aplicativo com seus dados atuais."
        }
    }
}

/// Envelope versionado do backup.
public struct BackupEnvelope: Codable, Sendable {
    public static let currentFormatVersion = 1

    /// Identificador do formato (protege contra arquivos parecidos).
    public var format: String
    public var formatVersion: Int
    public var exportedAt: Date
    /// Versão do aplicativo que gerou o backup (informativa).
    public var appVersion: String?

    public var speeches: [Speech]
    public var folders: [SpeechFolder]
    public var libraryItems: [LibraryItem]
    public var savedResearch: [SavedResearch]
    public var searchHistory: [SearchHistoryEntry]
    public var settings: AppSettings?
    public var readingProfiles: [ReadingProfile]

    public init(
        format: String = BackupEnvelope.formatIdentifier,
        formatVersion: Int = BackupEnvelope.currentFormatVersion,
        exportedAt: Date = Date(),
        appVersion: String? = nil,
        speeches: [Speech] = [],
        folders: [SpeechFolder] = [],
        libraryItems: [LibraryItem] = [],
        savedResearch: [SavedResearch] = [],
        searchHistory: [SearchHistoryEntry] = [],
        settings: AppSettings? = nil,
        readingProfiles: [ReadingProfile] = []
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.speeches = speeches
        self.folders = folders
        self.libraryItems = libraryItems
        self.savedResearch = savedResearch
        self.searchHistory = searchHistory
        self.settings = settings
        self.readingProfiles = readingProfiles
    }

    /// Assinatura do formato.
    public static let formatIdentifier = "discurso-biblico.backup"

    /// Resumo legível para a tela de restauração.
    public var summaryDescription: String {
        var parts: [String] = []
        parts.append("\(speeches.count) discurso\(speeches.count == 1 ? "" : "s")")
        if !libraryItems.isEmpty {
            parts.append("\(libraryItems.count) material\(libraryItems.count == 1 ? "" : "is")")
        }
        if !savedResearch.isEmpty {
            parts.append("\(savedResearch.count) pesquisa\(savedResearch.count == 1 ? "" : "s") salva\(savedResearch.count == 1 ? "" : "s")")
        }
        if !folders.isEmpty {
            parts.append("\(folders.count) pasta\(folders.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}

/// Conteúdo validado de um backup.
public struct BackupContents: Sendable {
    public var speeches: [Speech]
    public var folders: [SpeechFolder]
    public var libraryItems: [LibraryItem]
    public var savedResearch: [SavedResearch]
    public var searchHistory: [SearchHistoryEntry]
    public var settings: AppSettings?
    public var readingProfiles: [ReadingProfile]
    public var exportedAt: Date
    /// Avisos de compatibilidade (ex.: registro de versão mais nova).
    public var warnings: [String]

    public init(
        speeches: [Speech] = [],
        folders: [SpeechFolder] = [],
        libraryItems: [LibraryItem] = [],
        savedResearch: [SavedResearch] = [],
        searchHistory: [SearchHistoryEntry] = [],
        settings: AppSettings? = nil,
        readingProfiles: [ReadingProfile] = [],
        exportedAt: Date = Date(),
        warnings: [String] = []
    ) {
        self.speeches = speeches
        self.folders = folders
        self.libraryItems = libraryItems
        self.savedResearch = savedResearch
        self.searchHistory = searchHistory
        self.settings = settings
        self.readingProfiles = readingProfiles
        self.exportedAt = exportedAt
        self.warnings = warnings
    }
}

/// Estratégia de mesclagem na restauração.
public enum BackupMergeStrategy: String, Codable, CaseIterable, Sendable {
    /// Substitui os dados atuais pelos do backup.
    case replace
    /// Mantém o que existe e acrescenta o que falta (itens mais novos vencem
    /// quando o identificador coincide).
    case merge

    public var displayName: String {
        switch self {
        case .replace: return "Substituir tudo"
        case .merge: return "Combinar com os dados atuais"
        }
    }
}

public enum BackupService {

    // MARK: - Exportação

    /// Monta o envelope com os dados fornecidos.
    public static func makeEnvelope(
        speeches: [Speech],
        folders: [SpeechFolder] = [],
        libraryItems: [LibraryItem] = [],
        savedResearch: [SavedResearch] = [],
        searchHistory: [SearchHistoryEntry] = [],
        settings: AppSettings? = nil,
        readingProfiles: [ReadingProfile] = [],
        appVersion: String? = nil,
        now: Date = Date()
    ) -> BackupEnvelope {
        BackupEnvelope(
            exportedAt: now,
            appVersion: appVersion,
            speeches: speeches,
            folders: folders,
            libraryItems: libraryItems,
            savedResearch: savedResearch,
            searchHistory: searchHistory,
            settings: settings,
            readingProfiles: readingProfiles
        )
    }

    /// Serializa o envelope em JSON legível.
    public static func encoded(_ envelope: BackupEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(envelope)
        } catch {
            throw BackupError.unreadable(reason: error.localizedDescription)
        }
    }

    /// Exporta diretamente para os dados fornecidos.
    public static func export(
        speeches: [Speech],
        folders: [SpeechFolder] = [],
        libraryItems: [LibraryItem] = [],
        savedResearch: [SavedResearch] = [],
        searchHistory: [SearchHistoryEntry] = [],
        settings: AppSettings? = nil,
        readingProfiles: [ReadingProfile] = [],
        appVersion: String? = nil,
        now: Date = Date()
    ) throws -> Data {
        let envelope = makeEnvelope(
            speeches: speeches,
            folders: folders,
            libraryItems: libraryItems,
            savedResearch: savedResearch,
            searchHistory: searchHistory,
            settings: settings,
            readingProfiles: readingProfiles,
            appVersion: appVersion,
            now: now
        )
        return try encoded(envelope)
    }

    // MARK: - Restauração

    /// Valida e decodifica um backup, sem tocar nos dados atuais.
    public static func restore(data: Data) throws -> BackupContents {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Assinatura de formato (verificada antes da decodificação completa
        //    para dar uma mensagem melhor quando o arquivo é de outro app).
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.unreadable(reason: "o conteúdo não é JSON válido")
        }
        guard (object["format"] as? String) == BackupEnvelope.formatIdentifier else {
            throw BackupError.notABackup
        }
        guard let version = object["formatVersion"] as? Int else {
            throw BackupError.notABackup
        }
        guard version <= BackupEnvelope.currentFormatVersion else {
            throw BackupError.unsupportedVersion(version)
        }

        // 2. Decodificação completa.
        let envelope: BackupEnvelope
        do {
            envelope = try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw BackupError.unreadable(reason: (error as? DecodingError).map(Self.describe) ?? error.localizedDescription)
        }

        // 3. Avisos de compatibilidade por registro.
        var warnings: [String] = []
        let speechesFromNewerSchema = envelope.speeches.filter { $0.schemaVersion > Speech.currentSchemaVersion }
        if !speechesFromNewerSchema.isEmpty {
            warnings.append("\(speechesFromNewerSchema.count) discurso(s) foram gravados por uma versão mais nova; campos desconhecidos podem ser ignorados.")
        }
        let itemsFromNewerSchema = envelope.libraryItems.filter { $0.schemaVersion > LibraryItem.currentSchemaVersion }
        if !itemsFromNewerSchema.isEmpty {
            warnings.append("\(itemsFromNewerSchema.count) material(is) da biblioteca foram gravados por uma versão mais nova.")
        }

        if envelope.speeches.isEmpty,
           envelope.libraryItems.isEmpty,
           envelope.savedResearch.isEmpty,
           envelope.settings == nil,
           envelope.folders.isEmpty {
            throw BackupError.emptyBackup
        }

        return BackupContents(
            speeches: envelope.speeches,
            folders: envelope.folders,
            libraryItems: envelope.libraryItems,
            savedResearch: envelope.savedResearch,
            searchHistory: envelope.searchHistory,
            settings: envelope.settings,
            readingProfiles: envelope.readingProfiles,
            exportedAt: envelope.exportedAt,
            warnings: warnings
        )
    }

    /// Valida um arquivo antes de mostrar o botão de restauração.
    public static func inspect(data: Data) -> Result<BackupContents, BackupError> {
        do {
            return .success(try restore(data: data))
        } catch let error as BackupError {
            return .failure(error)
        } catch {
            return .failure(.unreadable(reason: error.localizedDescription))
        }
    }

    // MARK: - Mesclagem

    /// Combina o conteúdo do backup com os dados atuais.
    ///
    /// Na estratégia `.merge`, itens com o mesmo identificador são comparados
    /// por `updatedAt` (o mais recente vence); na `.replace`, os dados do
    /// backup substituem os atuais.
    public static func merge(
        backup: BackupContents,
        strategy: BackupMergeStrategy,
        currentSpeeches: [Speech] = [],
        currentFolders: [SpeechFolder] = [],
        currentLibraryItems: [LibraryItem] = [],
        currentSavedResearch: [SavedResearch] = []
    ) -> BackupContents {
        switch strategy {
        case .replace:
            return backup
        case .merge:
            var merged = backup

            var speechesByID: [UUID: Speech] = [:]
            for speech in currentSpeeches { speechesByID[speech.id] = speech }
            for speech in backup.speeches {
                if let existing = speechesByID[speech.id] {
                    speechesByID[speech.id] = speech.updatedAt >= existing.updatedAt ? speech : existing
                } else {
                    speechesByID[speech.id] = speech
                }
            }
            merged.speeches = speechesByID.values.sorted { $0.updatedAt > $1.updatedAt }

            var foldersByID: [UUID: SpeechFolder] = [:]
            for folder in currentFolders { foldersByID[folder.id] = folder }
            for folder in backup.folders where foldersByID[folder.id] == nil {
                foldersByID[folder.id] = folder
            }
            merged.folders = foldersByID.values.sorted { $0.sortIndex < $1.sortIndex }

            var itemsByID: [UUID: LibraryItem] = [:]
            for item in currentLibraryItems { itemsByID[item.id] = item }
            for item in backup.libraryItems {
                if let existing = itemsByID[item.id] {
                    itemsByID[item.id] = item.importedAt >= existing.importedAt ? item : existing
                } else {
                    itemsByID[item.id] = item
                }
            }
            merged.libraryItems = itemsByID.values.sorted { $0.importedAt > $1.importedAt }

            var researchByID: [UUID: SavedResearch] = [:]
            for saved in currentSavedResearch { researchByID[saved.id] = saved }
            for saved in backup.savedResearch {
                if let existing = researchByID[saved.id] {
                    researchByID[saved.id] = saved.savedAt >= existing.savedAt ? saved : existing
                } else {
                    researchByID[saved.id] = saved
                }
            }
            merged.savedResearch = researchByID.values.sorted { $0.savedAt > $1.savedAt }

            return merged
        }
    }

    // MARK: - Nome de arquivo

    /// Nome sugerido do arquivo de backup ("discurso-biblico-2026-10-15.json").
    public static func suggestedFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "discurso-biblico-\(formatter.string(from: now)).json"
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return "campo ausente: \(key.stringValue)"
        case .typeMismatch(let type, let context): return "tipo inesperado para \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(type)"
        case .valueNotFound(let type, let context): return "valor ausente para \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(type)"
        case .dataCorrupted(let context): return "dados inválidos: \(context.debugDescription)"
        @unknown default: return "formato inválido"
        }
    }
}
