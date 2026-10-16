//
//  DiscursoBiblicoApp.swift
//  DiscursoBiblico
//
//  Ponto de entrada do aplicativo.
//
//  O AppDelegate existe por um motivo só: permitir travar a orientação em
//  retrato durante o modo de proferimento, quando o usuário escolher isso.
//

import SwiftUI
import UIKit

@main
struct DiscursoBiblicoApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task {
                    await environment.network.start()
                    await environment.start()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationController.currentMask
    }
}
