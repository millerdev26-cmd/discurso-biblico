//
//  CommonViews.swift
//  DiscursoBiblico
//
//  Pequenos componentes usados em várias telas.
//

import DiscursoCore
import SwiftUI

/// Selo com a situação do discurso.
struct SpeechStatusChip: View {

    let status: SpeechStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .preparing: return .orange
        case .ready: return .green
        case .delivered: return .blue
        case .archived: return .secondary
        }
    }
}

/// Progresso de preparação (barra fina).
struct PreparationProgressView: View {

    let progress: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Preparação")
        .accessibilityValue("\(Int(progress * 100)) por cento")
    }
}

/// Duração em texto curto ("12 min" / "1 h 5 min").
struct DurationText: View {

    let minutes: Double
    var prefix: String?

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var text: String {
        let total = Int(minutes.rounded())
        let value: String
        if total >= 60 {
            let hours = total / 60
            let rest = total % 60
            value = rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
        } else {
            value = "\(total) min"
        }
        return prefix.map { "\($0) \(value)" } ?? value
    }
}

/// Estado vazio padronizado.
struct EmptyStateView: View {

    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
    }
}

/// Faixa de erro/aviso com botão de fechar.
struct MessageBanner: View {

    enum Kind {
        case error
        case info
        case warning

        var color: Color {
            switch self {
            case .error: return .red
            case .info: return .blue
            case .warning: return .orange
            }
        }

        var systemImage: String {
            switch self {
            case .error: return "exclamationmark.octagon.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }

    let kind: Kind
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.color)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Fechar aviso")
            }
        }
        .padding(10)
        .background(kind.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }
}

/// Linha com ícone e texto (usada nas listas de detalhes).
struct IconTextLabel: View {

    let systemImage: String
    let text: String
    var secondary = false

    var body: some View {
        Label {
            Text(text)
                .font(secondary ? .footnote : .body)
                .foregroundStyle(secondary ? .secondary : .primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
    }
}
