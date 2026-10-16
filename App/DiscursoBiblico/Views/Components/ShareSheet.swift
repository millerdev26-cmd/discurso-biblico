//
//  ShareSheet.swift
//  DiscursoBiblico
//
//  Folha de compartilhamento do sistema (exportação de arquivos e backup).
//  Nada é enviado a servidores: quem compartilha é o próprio usuário.
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.popoverPresentationController?.permittedArrowDirections = []
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
