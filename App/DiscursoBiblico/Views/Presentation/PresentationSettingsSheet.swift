//
//  PresentationSettingsSheet.swift
//  DiscursoBiblico
//
//  Ajustes do modo de proferimento, aplicados **durante** a apresentação.
//
//  Tudo o que se muda aqui vale na hora (o texto é remontado) e é guardado no
//  discurso ao sair, para o próximo discurso começar igual.
//

import DiscursoCore
import SwiftUI

struct PresentationSettingsSheet: View {

    let model: PresentationViewModel

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var isSaveProfilePresented = false
    @State private var profileName = ""

    var body: some View {
        NavigationStack {
            Form {
                textSection
                colorsSection
                autoScrollSection
                comfortSection
                duringSpeechSection
                profilesSection
            }
            .navigationTitle("Apresentação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pronto") { dismiss() }
                }
            }
            .alert("Salvar como perfil", isPresented: $isSaveProfilePresented) {
                TextField("Nome do perfil", text: $profileName)
                Button("Salvar") { saveProfile() }
                Button("Cancelar", role: .cancel) { profileName = "" }
            } message: {
                Text("O perfil guarda estas preferências para usar em outros discursos.")
            }
        }
    }

    // MARK: Seções

    private var textSection: some View {
        Section("Texto") {
            slider(
                "Tamanho",
                value: binding(\.fontSize),
                range: PresentationPreferences.fontSizeRange,
                step: PresentationPreferences.fontSizeStep,
                valueLabel: "\(Int(model.preferences.fontSize)) pt"
            )
            slider(
                "Altura das linhas",
                value: binding(\.lineHeightMultiple),
                range: PresentationPreferences.lineHeightRange,
                step: 0.05,
                valueLabel: String(format: "%.2f×", model.preferences.lineHeightMultiple)
            )
            slider(
                "Espaço entre parágrafos",
                value: binding(\.paragraphSpacing),
                range: PresentationPreferences.paragraphSpacingRange,
                step: 0.1,
                valueLabel: String(format: "%.1f", model.preferences.paragraphSpacing)
            )
            slider(
                "Largura da coluna",
                value: binding(\.columnWidthFraction),
                range: PresentationPreferences.columnWidthRange,
                step: 0.05,
                valueLabel: "\(Int(model.preferences.columnWidthFraction * 100))%"
            )
            slider(
                "Margem lateral",
                value: binding(\.horizontalMargin),
                range: PresentationPreferences.horizontalMarginRange,
                step: 4,
                valueLabel: "\(Int(model.preferences.horizontalMargin)) pt"
            )
            Picker("Fonte", selection: binding(\.fontDesign)) {
                ForEach(ReadingFontDesign.allCases, id: \.self) { design in
                    Text(design.displayName).tag(design)
                }
            }
            Picker("Alinhamento", selection: binding(\.alignment)) {
                ForEach(ReadingTextAlignment.allCases, id: \.self) { alignment in
                    Text(alignment.displayName).tag(alignment)
                }
            }
            Toggle("Texto em negrito", isOn: binding(\.usesBoldText))
        }
    }

    private var colorsSection: some View {
        Section("Cores") {
            Picker("Tema", selection: binding(\.theme)) {
                ForEach(ReadingTheme.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var autoScrollSection: some View {
        Section {
            slider(
                "Velocidade",
                value: binding(\.autoScrollSpeed),
                range: PresentationPreferences.autoScrollSpeedRange,
                step: PresentationPreferences.autoScrollSpeedStep,
                valueLabel: model.preferences.autoScrollSpeedDescription
            )
            Picker("Ao tocar na tela", selection: binding(\.autoScrollInteractionPolicy)) {
                ForEach(AutoScrollInteractionPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            slider(
                "Tempo para retomar",
                value: binding(\.autoScrollResumeDelay),
                range: PresentationPreferences.autoScrollResumeDelayRange,
                step: 1,
                valueLabel: "\(Int(model.preferences.autoScrollResumeDelay)) s"
            )
        } header: {
            Text("Rolagem automática")
        } footer: {
            Text("A rolagem sempre começa desligada e para no fim do texto ou após 30 minutos seguidos, por segurança.")
        }
    }

    private var comfortSection: some View {
        Section("Conforto") {
            Toggle("Manter a tela ligada", isOn: binding(\.keepsScreenAwake))
            Toggle("Travar em retrato", isOn: binding(\.locksPortraitOrientation))
            Toggle("Ocultar barra de status", isOn: binding(\.hidesSystemInterface))
            Toggle("Confirmar antes de sair", isOn: binding(\.confirmsExit))
        }
    }

    private var duringSpeechSection: some View {
        Section("Durante o discurso") {
            Toggle("Mostrar observações particulares", isOn: binding(\.showsPresenterNotes))
            Toggle("Mostrar progresso e tempo", isOn: binding(\.showsProgress))
            Toggle("Destacar referências bíblicas", isOn: binding(\.highlightsReferences))
        }
    }

    private var profilesSection: some View {
        Section {
            ForEach(environment.readingProfiles) { profile in
                Button {
                    model.apply(profile: profile)
                    Task {
                        await environment.saveSettings { $0.lastUsedReadingProfileID = profile.id }
                    }
                } label: {
                    HStack {
                        Text(profile.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if profile.preferences == model.preferences {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if !profile.isBuiltIn {
                        Button("Apagar", role: .destructive) {
                            let remaining = environment.readingProfiles.filter { $0.id != profile.id }
                            Task { await environment.saveReadingProfiles(remaining) }
                        }
                    }
                }
            }
            Button("Salvar como perfil…") {
                profileName = ""
                isSaveProfilePresented = true
            }
        } header: {
            Text("Perfis de leitura")
        } footer: {
            Text("Perfis guardam o conjunto de ajustes (texto, cores, rolagem) para reutilizar.")
        }
    }

    // MARK: Apoio

    private func binding<T>(_ keyPath: WritableKeyPath<PresentationPreferences, T>) -> Binding<T> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { newValue in model.updatePreferences { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(valueLabel)
        }
    }

    private func saveProfile() {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let profile = ReadingProfile(
            name: trimmed,
            preferences: model.preferences,
            isBuiltIn: false
        )
        var profiles = environment.readingProfiles
        profiles.append(profile)
        Task {
            await environment.saveReadingProfiles(profiles)
            await environment.saveSettings { $0.lastUsedReadingProfileID = profile.id }
        }
        profileName = ""
    }
}
