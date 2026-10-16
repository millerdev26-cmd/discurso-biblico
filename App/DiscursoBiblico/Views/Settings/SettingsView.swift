//
//  SettingsView.swift
//  DiscursoBiblico
//
//  Ajustes: leitura e preparação, perfis, regras de pesquisa, backup e
//  privacidade.
//
//  Tudo é gravado no aparelho. Não há conta, telemetria, anúncios nem
//  qualquer envio automático de dados.
//

import DiscursoCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var model: SettingsViewModel?
    @State private var providers: [(id: String, displayName: String, requiresNetwork: Bool)] = []
    @State private var shareItem: ShareItem?
    @State private var isImporterPresented = false
    @State private var pendingRestoreURL: URL?
    @State private var isRestoreSheetPresented = false
    @State private var isProfileNameAlertPresented = false
    @State private var profileNameDraft = ""
    @State private var isResetAlertPresented = false

    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView("Carregando ajustes…")
                }
            }
            .navigationTitle("Ajustes")
        }
        .task { await prepareModel() }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingRestoreURL = url
                Task {
                    await model?.inspectBackup(fileURL: url)
                    isRestoreSheetPresented = true
                }
            case .failure(let error):
                print("Escolha de backup cancelada/falhou: \(error.localizedDescription)")
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $isRestoreSheetPresented) {
            restoreSheet
        }
        .alert("Nome do perfil", isPresented: $isProfileNameAlertPresented) {
            TextField("Nome", text: $profileNameDraft)
            Button("Salvar") { saveProfile() }
            Button("Cancelar", role: .cancel) { profileNameDraft = "" }
        } message: {
            Text("O perfil guarda as preferências de apresentação atuais.")
        }
        .alert("Apagar ajustes e dados de pesquisa?", isPresented: $isResetAlertPresented) {
            Button("Apagar", role: .destructive) {
                Task {
                    await model?.clearSearchHistory()
                    await model?.clearResearchCache()
                    await model?.load()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Histórico de pesquisas e resultados guardados serão apagados. Discursos e materiais da biblioteca não são tocados.")
        }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func content(_ model: SettingsViewModel) -> some View {
        Form {
            if let message = model.lastMessage {
                Section {
                    MessageBanner(kind: .info, message: message)
                }
            }
            if let message = model.errorMessage {
                Section {
                    MessageBanner(kind: .error, message: message)
                }
            }

            readingSection(model)
            presentationDefaultsSection(model)
            profilesSection(model)
            researchSection(model)
            backupSection(model)
            privacySection
            aboutSection
        }
        .onChange(of: model.settings) { _, _ in
            Task { await model.persist() }
        }
    }

    // MARK: Leitura

    private func readingSection(_ model: SettingsViewModel) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Ritmo de fala")
                    Spacer()
                    Text("\(Int(model.settings.wordsPerMinute)) palavras/min")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { model.settings.wordsPerMinute },
                    set: { model.settings.wordsPerMinute = $0 }
                ), in: 100...200, step: 5)
                .accessibilityValue("\(Int(model.settings.wordsPerMinute)) palavras por minuto")
            }

            Picker("Ordenar discursos por", selection: Binding(
                get: { model.settings.preferredSpeechSort },
                set: { model.settings.preferredSpeechSort = $0 }
            )) {
                ForEach(SpeechSortOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } header: {
            Text("Leitura e preparação")
        } footer: {
            Text("O ritmo de fala é usado para estimar a duração dos discursos. Ajuste entre 100 e 200 palavras por minuto.")
        }
    }

    private func presentationDefaults(_ model: SettingsViewModel) -> some View {
        Group {
            Picker("Tema do modo de proferimento", selection: Binding(
                get: { model.settings.defaultPresentation.theme },
                set: { model.settings.defaultPresentation.theme = $0 }
            )) {
                ForEach(ReadingTheme.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Tamanho do texto")
                    Spacer()
                    Text("\(Int(model.settings.defaultPresentation.fontSize)) pt")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { model.settings.defaultPresentation.fontSize },
                    set: { model.settings.defaultPresentation.fontSize = $0 }
                ), in: PresentationPreferences.fontSizeRange, step: PresentationPreferences.fontSizeStep)
            }

            Toggle("Manter a tela ligada por padrão", isOn: Binding(
                get: { model.settings.defaultPresentation.keepsScreenAwake },
                set: { model.settings.defaultPresentation.keepsScreenAwake = $0 }
            ))

            Toggle("Destacar referências bíblicas", isOn: Binding(
                get: { model.settings.defaultPresentation.highlightsReferences },
                set: { model.settings.defaultPresentation.highlightsReferences = $0 }
            ))
        }
    }

    // MARK: Perfis

    private func presentationDefaultsSection(_ model: SettingsViewModel) -> some View {
        Section {
            presentationDefaults(model)
        } header: {
            Text("Modo de proferimento (padrões)")
        } footer: {
            Text("Estes valores valem para discursos novos e para os que ainda não têm preferências próprias.")
        }
    }

    private func profilesSection(_ model: SettingsViewModel) -> some View {
        Section {
            ForEach(model.profiles) { profile in
                Button {
                    model.settings.lastUsedReadingProfileID = profile.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .foregroundStyle(.primary)
                            Text(profileSummary(profile))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.settings.lastUsedReadingProfileID == profile.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .contextMenu {
                    Button {
                        applyProfile(profile, to: model)
                    } label: {
                        Label("Copiar para os padrões", systemImage: "doc.on.doc")
                    }
                    if !profile.isBuiltIn {
                        Button(role: .destructive) {
                            model.profiles.removeAll { $0.id == profile.id }
                            Task { await model.persistProfiles() }
                        } label: {
                            Label("Apagar perfil", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                profileNameDraft = ""
                isProfileNameAlertPresented = true
            } label: {
                Label("Salvar preferências atuais como perfil…", systemImage: "plus")
            }
        } header: {
            Text("Perfis de leitura")
        } footer: {
            Text("O perfil marcado com ✓ é usado como ponto de partida no modo de proferimento.")
        }
    }

    private func profileSummary(_ profile: ReadingProfile) -> String {
        let preferences = profile.preferences
        return "\(Int(preferences.fontSize)) pt · \(preferences.theme.displayName) · rolagem \(preferences.autoScrollSpeedDescription)"
    }

    // MARK: Pesquisa

    private func researchSection(_ model: SettingsViewModel) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Intervalo entre consultas")
                    Spacer()
                    Text("\(Int(model.settings.researchPolicy.minimumRequestInterval)) s")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { model.settings.researchPolicy.minimumRequestInterval },
                    set: { model.settings.researchPolicy.minimumRequestInterval = $0 }
                ), in: 1...60, step: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Máximo de resultados")
                    Spacer()
                    Text("\(model.settings.researchPolicy.maximumResults)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(model.settings.researchPolicy.maximumResults) },
                    set: { model.settings.researchPolicy.maximumResults = Int($0) }
                ), in: 5...100, step: 5)
            }

            Toggle("Preferir resultados guardados (modo econômico)", isOn: Binding(
                get: { model.settings.researchPolicy.preferCache },
                set: { model.settings.researchPolicy.preferCache = $0 }
            ))

            Toggle("Consultar a página pública de resultados", isOn: Binding(
                get: { model.settings.researchPolicy.allowsPublicSearchPage },
                set: { model.settings.researchPolicy.allowsPublicSearchPage = $0 }
            ))

            Toggle("Oferecer links oficiais quando a consulta não for possível", isOn: Binding(
                get: { model.settings.researchPolicy.allowsOfficialLinkFallback },
                set: { model.settings.researchPolicy.allowsOfficialLinkFallback = $0 }
            ))

            DisclosureGroup("Provedores") {
                ForEach(providers, id: \.id) { provider in
                    Toggle(isOn: Binding(
                        get: { model.isProviderEnabled(provider.id) },
                        set: { enabled in
                            Task { await model.setProvider(provider.id, enabled: enabled) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                            if provider.requiresNetwork {
                                Text("Usa internet · com limite de uso")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Button {
                isResetAlertPresented = true
            } label: {
                Label("Apagar histórico e resultados guardados", systemImage: "trash")
            }
        } header: {
            Text("Pesquisa")
        } footer: {
            Text("A identificação enviada às fontes oficiais é “\(AppSettings.defaultUserAgent)”. Nenhuma página é baixada em massa e não há tentativa de contornar bloqueios.")
        }
    }

    // MARK: Backup

    private func backupSection(_ model: SettingsViewModel) -> some View {
        Section {
            Button {
                Task {
                    await model.exportBackup()
                    if let url = model.backupFileURL {
                        shareItem = ShareItem(url: url)
                    }
                }
            } label: {
                Label("Exportar backup (compartilhar arquivo)", systemImage: "square.and.arrow.up")
            }
            .disabled(model.isWorking)

            if let summary = model.backupSummary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                isImporterPresented = true
            } label: {
                Label("Restaurar de um arquivo…", systemImage: "square.and.arrow.down")
            }
            .disabled(model.isWorking)

            if model.isWorking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Trabalhando…")
                        .font(.footnote)
                }
            }

            if let preview = model.restorePreview {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup selecionado")
                        .font(.footnote.weight(.semibold))
                    Text(preview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("O backup guarda discursos, materiais da biblioteca, fontes salvas, perfis e ajustes em um único arquivo JSON. Guarde-o em local seguro.")
        }
    }

    private var restoreSheet: some View {
        NavigationStack {
            Form {
                if let model {
                    Section {
                        if let preview = model.restorePreview {
                            Text(preview)
                        } else {
                            Text("Não foi possível ler o arquivo escolhido.")
                        }
                    } header: {
                        Text("Conteúdo do backup")
                    }

                    Section {
                        Picker("Como aplicar", selection: Binding(
                            get: { model.restoreStrategy },
                            set: { model.restoreStrategy = $0 }
                        )) {
                            ForEach(BackupMergeStrategy.allCases, id: \.self) { strategy in
                                Text(strategy.displayName).tag(strategy)
                            }
                        }
                    } header: {
                        Text("Estratégia")
                    } footer: {
                        Text("“Combinar” mantém o que já existe e acrescenta o que vem do arquivo. “Substituir” usa a versão do backup quando o mesmo item aparece nos dois lados.")
                    }

                    if let message = model.errorMessage {
                        Section {
                            MessageBanner(kind: .error, message: message)
                        }
                    }
                }
            }
            .navigationTitle("Restaurar backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        isRestoreSheetPresented = false
                        pendingRestoreURL = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restaurar") {
                        Task { await performRestore() }
                    }
                    .disabled(pendingRestoreURL == nil || model?.isWorking == true)
                }
            }
        }
    }

    // MARK: Privacidade

    private var privacySection: some View {
        Section {
            Label("Tudo é guardado neste aparelho", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
            Text("O aplicativo não cria conta, não envia telemetria, não exibe anúncios e não envia seus discursos a lugar nenhum. A única conexão de rede acontece quando você pede uma pesquisa, e ela respeita os limites de uso das fontes oficiais.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Privacidade")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Versão", value: appVersion)
            LabeledContent("Núcleo", value: "DiscursoCore (testado no Linux)")
            Text("O aplicativo não redistribui traduções da Bíblia: as referências abrem a fonte oficial ou usam o texto que você mesmo importou. DOCX e JWPUB não são suportados nesta versão.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Sobre")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: Ações

    private func prepareModel() async {
        if model == nil {
            model = SettingsViewModel(
                settingsRepository: environment.settingsRepository,
                backup: environment.backup,
                researchRepository: environment.researchRepository,
                researchService: environment.research
            )
        }
        await model?.load()
        providers = await environment.research.availableProviders()
    }

    private func saveProfile() {
        let name = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        profileNameDraft = ""
        guard !name.isEmpty, let model else { return }
        let profile = ReadingProfile(name: name, preferences: model.settings.defaultPresentation, isBuiltIn: false)
        model.profiles.append(profile)
        model.settings.lastUsedReadingProfileID = profile.id
        Task { await model.persistProfiles() }
    }

    private func applyProfile(_ profile: ReadingProfile, to model: SettingsViewModel) {
        model.settings.defaultPresentation = profile.preferences
        model.settings.lastUsedReadingProfileID = profile.id
    }

    private func performRestore() async {
        guard let url = pendingRestoreURL, let model else { return }
        await model.restoreBackup(fileURL: url)
        await environment.loadSettingsAndProfiles()
        await environment.collectStorageWarnings()
        isRestoreSheetPresented = false
        pendingRestoreURL = nil
        await model.load()
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview())
}
