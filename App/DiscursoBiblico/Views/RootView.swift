//
//  RootView.swift
//  DiscursoBiblico
//
//  Estrutura principal: quatro áreas (Discursos, Biblioteca, Pesquisar,
//  Ajustes). O modo de proferimento é aberto a partir de um discurso ou pelo
//  botão "Continuar".
//

import DiscursoCore
import SwiftUI

struct RootView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab: Tab = .speeches
    @State private var showingWarnings = false

    enum Tab: Hashable {
        case speeches
        case library
        case research
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SpeechListView()
                .tabItem { Label("Discursos", systemImage: "text.book.closed") }
                .tag(Tab.speeches)

            LibraryListView()
                .tabItem { Label("Biblioteca", systemImage: "books.vertical") }
                .tag(Tab.library)

            ResearchView()
                .tabItem { Label("Pesquisar", systemImage: "magnifyingglass") }
                .tag(Tab.research)

            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.accentColor)
        .safeAreaInset(edge: .top) {
            if !environment.storageWarnings.isEmpty {
                recoveryBanner
            }
        }
        .sheet(isPresented: $showingWarnings) {
            NavigationStack {
                List(environment.storageWarnings, id: \.self) { warning in
                    Text(warning)
                }
                .navigationTitle("Avisos")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Entendi") {
                            showingWarnings = false
                            Task { await environment.acknowledgeStorageWarnings() }
                        }
                    }
                }
            }
        }
    }

    private var recoveryBanner: some View {
        Button {
            showingWarnings = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Há \(environment.storageWarnings.count) aviso(s) sobre seus dados. Toque para ver.")
                    .font(.footnote)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.yellow.opacity(0.22))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.preview())
}
