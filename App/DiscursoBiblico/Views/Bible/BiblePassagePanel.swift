//
//  BiblePassagePanel.swift
//  DiscursoBiblico
//
//  Painel de um trecho bíblico aberto durante a leitura/preparação.
//
//  Princípios (requisitos do projeto):
//   - o aplicativo **não redistribui** traduções da Bíblia;
//   - o painel sempre oferece o **link oficial** (wol.jw.org) e o atalho para
//     o aplicativo JW Library, quando instalado;
//   - nenhum texto é inventado: sem uma fonte importada pelo usuário, o painel
//     mostra apenas as opções de consulta.
//
//  O painel pode ser aberto durante a apresentação: ao fechar, o discurso
//  continua exatamente onde estava (a apresentação não é desmontada).
//

import DiscursoCore
import SwiftUI
import UIKit

struct BiblePassagePanel: View {

    let reference: BibleReference

    @Environment(\.dismiss) private var dismiss

    @State private var passage: BiblePassage?
    @State private var isOpeningErrorPresented = false
    @State private var openingErrorMessage = ""

    private let provider: any BibleTextProvider = OfficialLinkBibleProvider()

    var body: some View {
        NavigationStack {
            List {
                headerSection

                if let passage, !passage.verses.isEmpty {
                    versesSection(passage)
                }

                consultationSection

                if let notice = passage?.notice ?? defaultNotice {
                    Section {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Texto bíblico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Copiar referência") {
                        Clipboard.copy(reference.displayText)
                        Haptics.tap()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .task { await loadPassage() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Não foi possível abrir", isPresented: $isOpeningErrorPresented) {
            Button("Entendi", role: .cancel) {}
        } message: {
            Text(openingErrorMessage)
        }
    }

    // MARK: Seções

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(reference.displayText)
                    .font(.title3.weight(.semibold))
                Text(reference.abbreviatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if reference.totalVerses > 0 {
                    Text("\(reference.totalVerses) versículo(s) nesta referência")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func versesSection(_ passage: BiblePassage) -> some View {
        Section {
            ForEach(passage.verses, id: \.number) { verse in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(verse.number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                        .frame(minWidth: 22, alignment: .trailing)
                    Text(verse.text)
                }
            }
        } header: {
            Text(passage.sourceName ?? "Texto importado")
        }
    }

    private var consultationSection: some View {
        Section {
            if let url = passage?.officialURL ?? reference.officialWebURL() {
                Button {
                    open(url, label: "a fonte oficial")
                } label: {
                    IconTextLabel(
                        systemImage: "safari",
                        text: "Abrir na fonte oficial (wol.jw.org)"
                    )
                }
            }

            if let deepLink = passage?.deepLink ?? reference.jwLibraryDeepLink() {
                Button {
                    open(deepLink, label: "o aplicativo JW Library")
                } label: {
                    IconTextLabel(
                        systemImage: "book.closed",
                        text: "Abrir no aplicativo JW Library"
                    )
                }
            }

            if let searchURL = reference.officialSearchURL() {
                Button {
                    open(searchURL, label: "a pesquisa oficial")
                } label: {
                    IconTextLabel(
                        systemImage: "magnifyingglass",
                        text: "Pesquisar esta referência no site oficial"
                    )
                }
            }
        } header: {
            Text("Consultar o texto")
        } footer: {
            Text("O aplicativo não guarda nem redistribui o texto bíblico: ele apenas abre o endereço oficial. O link do JW Library funciona se o aplicativo estiver instalado.")
        }
    }

    private var defaultNotice: String? {
        "Sem um texto importado por você, o painel mostra somente os caminhos oficiais para consulta."
    }

    // MARK: Ações

    private func loadPassage() async {
        do {
            passage = try await provider.passage(for: reference)
        } catch {
            passage = nil
        }
    }

    private func open(_ url: URL, label: String) {
        UIApplication.shared.open(url) { success in
            if !success {
                openingErrorMessage = "Não foi possível abrir \(label). Verifique o endereço ou copie a referência e consulte no navegador."
                isOpeningErrorPresented = true
            }
        }
    }
}

#Preview {
    BiblePassagePanel(reference: BibleReference(bookID: .john, chapter: 3, verseStart: 16, verseEnd: 17))
}
