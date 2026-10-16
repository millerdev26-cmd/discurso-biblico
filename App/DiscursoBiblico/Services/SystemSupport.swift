//
//  SystemSupport.swift
//  DiscursoBiblico
//
//  Integrações com o sistema usadas pelo modo de apresentação:
//   - manter a tela ligada durante o discurso;
//   - travar a orientação (retrato) quando o usuário pedir;
//   - vibração leve nos comandos (ajuda a operar sem olhar a tela).
//

import DiscursoCore
import Foundation
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Tela ligada

@MainActor
@Observable
final class ScreenAwakeController {

    private(set) var isActive = false

    /// Liga/desliga a manutenção da tela acesa.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = active
        #endif
    }

    /// Chamado ao sair da apresentação — nunca deixa a tela presa ligada.
    func releaseIfNeeded() {
        setActive(false)
    }
}

// MARK: - Orientação

/// Trava a orientação em retrato durante a apresentação, quando o usuário
/// escolher isso nas preferências.
@MainActor
@Observable
final class OrientationController {

    /// Máscara lida pelo `AppDelegate`.
    nonisolated(unsafe) static var currentMask: UIInterfaceOrientationMask = .allButUpsideDown

    private(set) var isLockedToPortrait = false

    func lockToPortrait(_ locked: Bool) {
        guard locked != isLockedToPortrait else { return }
        isLockedToPortrait = locked
        Self.currentMask = locked ? .portrait : .allButUpsideDown

        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: Self.currentMask))
        }
        #endif
    }
}

// MARK: - Vibração leve

@MainActor
enum Haptics {

    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

// MARK: - Área de transferência

@MainActor
enum Clipboard {

    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
