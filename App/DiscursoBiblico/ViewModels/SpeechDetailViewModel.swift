//
//  SpeechDetailViewModel.swift
//  DiscursoBiblico
//
//  Visão geral de um discurso: duração estimada × planejada, referências,
//  fontes, favorito, situação, exportação e leitura em voz alta.
//

import DiscursoCore
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SpeechDetailViewModel {

    private(set) var speech: Speech?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    // Exportação
    var exportFormat: SpeechExportFormat = .plainText
    var includePresenterNotes = true
    var includeSources = true
    var includeMetadata = true
    private(set) var lastExport: ExportOutcome?

    struct ExportOutcome: Identifiable {
        let id = UUID()
        var fileURL: URL
        var message: String
    }

    var wordsPerMinute: Double = SpeechDurationEstimator.defaultWordsPerMinute

    private let repository: any SpeechRepository

    init(repository: any SpeechRepository) {
        self.repository = repository
    }

    func load(id: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            speech = try await repository.load(id: id)
            errorMessage = nil
        } catch {
            errorMessage = "Não foi possível abrir o discurso (\(error.localizedDescription))."
        }
    }

    func save() async {
        guard let speech else { return }
        try? await repository.save(speech)
    }

    private func mutate(_ change: (inout Speech) -> Void) async {
        guard var copy = speech else { return }
        change(&copy)
        copy.updatedAt = Date()
        speech = copy
        try? await repository.save(copy)
    }

    // MARK: Ações

    func toggleFavorite() async {
        await mutate { $0.isFavorite.toggle() }
    }

    func setStatus(_ status: SpeechStatus) async {
        await mutate { $0.status = status }
    }

    func setPlannedMinutes(_ minutes: Double?) async {
        await mutate { $0.plannedMinutes = minutes }
    }

    func markPrepared() async {
        await mutate { speech in
            speech.status = .ready
            for index in speech.sections.indices {
                speech.sections[index].isCompleted = true
            }
        }
    }

    func resetReadingPosition() async {
        await mutate { $0.lastReadPosition = nil }
    }

    // MARK: Informações

    var estimate: SpeechDurationEstimate? {
        speech.map { SpeechDurationEstimator.estimate(speech: $0, wordsPerMinute: wordsPerMinute) }
    }

    var durationSummary: String {
        guard let speech, let estimate else { return "—" }
        let estimated = Self.minutesText(estimate.totalMinutes)
        if let planned = speech.plannedMinutes {
            let delta = estimate.totalMinutes - planned
            let sign = delta >= 0 ? "+" : "−"
            return "\(estimated) (estimado) · \(Self.minutesText(planned)) (planejado) · \(sign)\(Self.minutesText(abs(delta)))"
        }
        return "\(estimated) estimados"
    }

    var references: [(String, BibleReference)] {
        (speech?.references ?? []).map { ($0.displayText, $0) }
    }

    // MARK: Exportação

    /// Gera o arquivo escolhido (TXT/Markdown/HTML/PDF) em pasta temporária.
    func export() async {
        guard let speech else { return }
        let options = SpeechExportOptions(
            includePresenterNotes: includePresenterNotes,
            includeSources: includeSources,
            includeMetadata: includeMetadata
        )
        do {
            let fileURL: URL
            let message: String
            if exportFormat == .pdf {
                let request = try SpeechExporter.pdfRequest(for: speech, options: options)
                fileURL = try SpeechPDFRenderer.renderToTemporaryFile(request)
                message = "PDF gerado (\(request.suggestedFileName))."
            } else {
                let payload = try SpeechExporter.payload(for: speech, format: exportFormat, options: options)
                fileURL = try Self.write(payload.content, fileName: payload.suggestedFileName)
                message = "Arquivo \(exportFormat.displayName) gerado (\(payload.suggestedFileName))."
            }
            lastExport = ExportOutcome(fileURL: fileURL, message: message)
        } catch let error as SpeechExportError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível exportar (\(error.localizedDescription))."
        }
    }

    private static func write(_ content: String, fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscursoBiblico", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try Data(content.utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: Apoio

    static func minutesText(_ minutes: Double) -> String {
        let totalSeconds = Int((minutes * 60).rounded())
        let minutesPart = totalSeconds / 60
        let secondsPart = totalSeconds % 60
        if minutesPart == 0 { return "\(secondsPart) s" }
        if secondsPart == 0 { return "\(minutesPart) min" }
        return "\(minutesPart) min \(secondsPart) s"
    }
}
