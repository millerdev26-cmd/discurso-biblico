//
//  PresentationPreferences.swift
//  DiscursoCore
//
//  Preferências do modo de proferimento e perfis de leitura.
//
//  Todos os valores são validados (`sanitized()`): qualquer ajuste fora da
//  faixa é aproximado para o limite, o que protege a interface contra valores
//  corrompidos em disco ou vindos de backup de outra versão.
//

import Foundation

/// Tema de leitura.
public enum ReadingTheme: String, Codable, CaseIterable, Sendable {
    /// Segue o sistema (claro/escuro).
    case system
    /// Claro.
    case light
    /// Escuro.
    case dark
    /// Sépia (papel envelhecido), confortável em ambientes iluminados.
    case sepia
    /// Escuro com contraste reforçado.
    case highContrast

    public var displayName: String {
        switch self {
        case .system: return "Automático"
        case .light: return "Claro"
        case .dark: return "Escuro"
        case .sepia: return "Sépia"
        case .highContrast: return "Alto contraste"
        }
    }
}

/// Design tipográfico do texto na apresentação.
public enum ReadingFontDesign: String, Codable, CaseIterable, Sendable {
    case system
    case serif
    case rounded
    case monospaced

    public var displayName: String {
        switch self {
        case .system: return "Padrão"
        case .serif: return "Com serifa"
        case .rounded: return "Arredondada"
        case .monospaced: return "Monoespaçada"
        }
    }
}

/// Comportamento da rolagem automática quando o usuário toca na tela.
public enum AutoScrollInteractionPolicy: String, Codable, CaseIterable, Sendable {
    /// Pausa a rolagem automática e espera o usuário retomar.
    case pause
    /// Pausa e retoma automaticamente após alguns segundos.
    case pauseAndResume
    /// Continua rolando (não recomendado; útil em telas sem interação).
    case keepScrolling

    public var displayName: String {
        switch self {
        case .pause: return "Pausar até eu retomar"
        case .pauseAndResume: return "Pausar e retomar sozinho"
        case .keepScrolling: return "Continuar rolando"
        }
    }
}

/// Alinhamento do texto.
public enum ReadingTextAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case justified
    case center

    public var displayName: String {
        switch self {
        case .leading: return "À esquerda"
        case .justified: return "Justificado"
        case .center: return "Centralizado"
        }
    }
}

/// Preferências de apresentação (modo de proferimento).
public struct PresentationPreferences: Codable, Hashable, Sendable {

    // MARK: Tipografia

    /// Tamanho da fonte em pontos (iOS). Faixa: 16...96.
    public var fontSize: Double
    /// Multiplicador de altura de linha. Faixa: 1.0...2.5.
    public var lineHeightMultiple: Double
    /// Espaço extra entre parágrafos, em múltiplos do tamanho da fonte (0...2).
    public var paragraphSpacing: Double
    /// Fração da largura da tela usada pela coluna de texto (0.35...1.0).
    public var columnWidthFraction: Double
    /// Margem horizontal, em pontos (0...160).
    public var horizontalMargin: Double
    /// Design da fonte.
    public var fontDesign: ReadingFontDesign
    /// Alinhamento do texto.
    public var alignment: ReadingTextAlignment
    /// `true` para negrito geral (útil em ambientes com pouca luz).
    public var usesBoldText: Bool

    // MARK: Aparência

    public var theme: ReadingTheme

    // MARK: Rolagem

    /// Velocidade da rolagem automática em pontos por segundo (4...200).
    public var autoScrollSpeed: Double
    /// Comportamento quando o usuário interage com o texto.
    public var autoScrollInteractionPolicy: AutoScrollInteractionPolicy
    /// Segundos de espera antes de retomar (usado por `.pauseAndResume`, 1...30).
    public var autoScrollResumeDelay: Double

    // MARK: Comportamento

    /// Mantém a tela ligada durante a apresentação.
    public var keepsScreenAwake: Bool
    /// Bloqueia a rotação da tela (retrato) durante a apresentação.
    public var locksPortraitOrientation: Bool
    /// Exibe as notas do apresentador por padrão.
    public var showsPresenterNotes: Bool
    /// Exibe o indicador de progresso e a seção atual.
    public var showsProgress: Bool
    /// Destaca automaticamente as referências bíblicas encontradas no texto.
    public var highlightsReferences: Bool
    /// Oculta barras e relógio do sistema durante a leitura.
    public var hidesSystemInterface: Bool
    /// Confirma a saída do modo de proferimento.
    public var confirmsExit: Bool

    public static let `default` = PresentationPreferences()

    public init(
        fontSize: Double = 34,
        lineHeightMultiple: Double = 1.25,
        paragraphSpacing: Double = 0.6,
        columnWidthFraction: Double = 0.86,
        horizontalMargin: Double = 28,
        fontDesign: ReadingFontDesign = .serif,
        alignment: ReadingTextAlignment = .leading,
        usesBoldText: Bool = false,
        theme: ReadingTheme = .system,
        autoScrollSpeed: Double = 28,
        autoScrollInteractionPolicy: AutoScrollInteractionPolicy = .pause,
        autoScrollResumeDelay: Double = 5,
        keepsScreenAwake: Bool = true,
        locksPortraitOrientation: Bool = false,
        showsPresenterNotes: Bool = false,
        showsProgress: Bool = true,
        highlightsReferences: Bool = true,
        hidesSystemInterface: Bool = false,
        confirmsExit: Bool = true
    ) {
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        self.paragraphSpacing = paragraphSpacing
        self.columnWidthFraction = columnWidthFraction
        self.horizontalMargin = horizontalMargin
        self.fontDesign = fontDesign
        self.alignment = alignment
        self.usesBoldText = usesBoldText
        self.theme = theme
        self.autoScrollSpeed = autoScrollSpeed
        self.autoScrollInteractionPolicy = autoScrollInteractionPolicy
        self.autoScrollResumeDelay = autoScrollResumeDelay
        self.keepsScreenAwake = keepsScreenAwake
        self.locksPortraitOrientation = locksPortraitOrientation
        self.showsPresenterNotes = showsPresenterNotes
        self.showsProgress = showsProgress
        self.highlightsReferences = highlightsReferences
        self.hidesSystemInterface = hidesSystemInterface
        self.confirmsExit = confirmsExit
    }

    // MARK: - Limites

    public static let fontSizeRange: ClosedRange<Double> = 16...96
    public static let lineHeightRange: ClosedRange<Double> = 1.0...2.5
    public static let paragraphSpacingRange: ClosedRange<Double> = 0...2
    public static let columnWidthRange: ClosedRange<Double> = 0.35...1.0
    public static let horizontalMarginRange: ClosedRange<Double> = 0...160
    public static let autoScrollSpeedRange: ClosedRange<Double> = 4...200
    public static let autoScrollResumeDelayRange: ClosedRange<Double> = 1...30

    /// Ajusta todos os valores para as faixas válidas.
    public func sanitized() -> PresentationPreferences {
        var copy = self
        copy.fontSize = fontSize.clamped(to: Self.fontSizeRange)
        copy.lineHeightMultiple = lineHeightMultiple.clamped(to: Self.lineHeightRange)
        copy.paragraphSpacing = paragraphSpacing.clamped(to: Self.paragraphSpacingRange)
        copy.columnWidthFraction = columnWidthFraction.clamped(to: Self.columnWidthRange)
        copy.horizontalMargin = horizontalMargin.clamped(to: Self.horizontalMarginRange)
        copy.autoScrollSpeed = autoScrollSpeed.clamped(to: Self.autoScrollSpeedRange)
        copy.autoScrollResumeDelay = autoScrollResumeDelay.clamped(to: Self.autoScrollResumeDelayRange)
        if !copy.fontSize.isFinite { copy.fontSize = Self.default.fontSize }
        if !copy.lineHeightMultiple.isFinite { copy.lineHeightMultiple = Self.default.lineHeightMultiple }
        if !copy.autoScrollSpeed.isFinite { copy.autoScrollSpeed = Self.default.autoScrollSpeed }
        return copy
    }

    // MARK: - Ajustes rápidos

    /// Passo de aumento/diminuição de fonte usado pelos botões "A+"/"A-".
    public static let fontSizeStep: Double = 4

    public mutating func increaseFontSize() {
        fontSize = (fontSize + Self.fontSizeStep).clamped(to: Self.fontSizeRange)
    }

    public mutating func decreaseFontSize() {
        fontSize = (fontSize - Self.fontSizeStep).clamped(to: Self.fontSizeRange)
    }

    /// Passo de ajuste da velocidade da rolagem automática.
    public static let autoScrollSpeedStep: Double = 6

    public mutating func increaseAutoScrollSpeed() {
        autoScrollSpeed = (autoScrollSpeed + Self.autoScrollSpeedStep).clamped(to: Self.autoScrollSpeedRange)
    }

    public mutating func decreaseAutoScrollSpeed() {
        autoScrollSpeed = (autoScrollSpeed - Self.autoScrollSpeedStep).clamped(to: Self.autoScrollSpeedRange)
    }

    /// Velocidade relativa em porcentagem, para exibição (1.0 = padrão).
    public var autoScrollSpeedDescription: String {
        let reference = Self.default.autoScrollSpeed
        let percentage = Int((autoScrollSpeed / reference * 100).rounded())
        return "\(percentage)%"
    }
}

/// Perfil de leitura salvo pelo usuário ("Leitura normal", "Fonte grande"...).
public struct ReadingProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var preferences: PresentationPreferences
    public var isBuiltIn: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        preferences: PresentationPreferences,
        isBuiltIn: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.preferences = preferences
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }

    /// Perfis prontos sugeridos pelo aplicativo.
    public static var builtInProfiles: [ReadingProfile] {
        [
            ReadingProfile(
                name: "Leitura normal",
                preferences: PresentationPreferences(),
                isBuiltIn: true
            ),
            ReadingProfile(
                name: "Fonte grande",
                preferences: {
                    var preferences = PresentationPreferences()
                    preferences.fontSize = 54
                    preferences.lineHeightMultiple = 1.35
                    preferences.usesBoldText = true
                    return preferences
                }(),
                isBuiltIn: true
            ),
            ReadingProfile(
                name: "Ambiente escuro",
                preferences: {
                    var preferences = PresentationPreferences()
                    preferences.theme = .dark
                    preferences.fontSize = 40
                    return preferences
                }(),
                isBuiltIn: true
            ),
            ReadingProfile(
                name: "Rolagem automática",
                preferences: {
                    var preferences = PresentationPreferences()
                    preferences.autoScrollSpeed = 26
                    preferences.autoScrollInteractionPolicy = .pause
                    preferences.showsPresenterNotes = true
                    return preferences
                }(),
                isBuiltIn: true
            ),
            ReadingProfile(
                name: "Púlpito (alto contraste)",
                preferences: {
                    var preferences = PresentationPreferences()
                    preferences.theme = .highContrast
                    preferences.fontSize = 48
                    preferences.usesBoldText = true
                    preferences.columnWidthFraction = 0.8
                    return preferences
                }(),
                isBuiltIn: true
            )
        ]
    }
}

extension Comparable {
    /// Limita o valor à faixa informada.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
