//
//  NetworkMonitor.swift
//  DiscursoBiblico
//
//  Diz se há conexão — usado para avisar antes de tentar a pesquisa na
//  página pública e para escolher a situação "sem conexão" na interface.
//  O aplicativo não depende disto para funcionar: tudo que é local continua
//  disponível offline.
//

import DiscursoCore
import Foundation
import Network

actor NetworkMonitor {

    private let monitor = NWPathMonitor()
    private var isSatisfied = true
    private var started = false

    /// Última situação conhecida. Otimista no início (tenta a rede; se
    /// falhar, o próprio provedor devolve `offline`).
    var isOnline: Bool { isSatisfied }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { await self.update(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "br.org.discursobiblico.network"))
    }

    func stop() {
        monitor.cancel()
        started = false
    }

    private func update(_ value: Bool) {
        isSatisfied = value
    }
}
