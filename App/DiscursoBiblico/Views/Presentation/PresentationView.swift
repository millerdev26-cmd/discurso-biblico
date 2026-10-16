//
//  PresentationView.swift
//  DiscursoBiblico
//
//  Tela principal do modo de proferimento.
//
//  Princípios de uso durante o discurso:
//   - o texto domina a tela; os controles aparecem só quando chamados;
//   - nada rola sozinho sem o usuário ligar;
//   - qualquer toque/arrasto pausa a rolagem automática;
//   - o ponto de leitura volta exatamente onde parou;
//   - a tela não apaga e a orientação fica como o usuário escolheu.
//

import DiscursoCore
import SwiftUI

struct PresentationView: View {

    let speechID: UUID

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var model: PresentationViewModel?
    @State private var loadErrorMessage: String?
    @State private var showingSettings = false
    @State private var passage: PassageRequest?
    @State private var isExitAlertPresented = false

    /// Envelope identificável para apresentar o painel de um trecho bíblico.
    struct PassageRequest: Identifiable {
        let id = UUID()
        let reference: BibleReference
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if let loadErrorMessage {
                ContentUnavailableView {
                    Label("Não foi possível abrir o discurso", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadErrorMessage)
                } actions: {
                    Button("Voltar") { dismiss() }
                }
            } else {
                ProgressView("Preparando…")
                    .task { await load() }
            }
        }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func content(_ model: PresentationViewModel) -> some View {
        @Bindable var model = model
        let palette = PresentationThemeColors(
            preferences: model.preferences,
            colorScheme: colorScheme
        )

        ZStack {
            palette.background.ignoresSafeArea()

            PresentationTextView(
                attributedText: model.attributedText,
                horizontalInset: model.textHorizontalInset,
                targetOffset: model.targetOffset,
                pendingScrollToSection: model.pendingScrollToSection,
                sectionRanges: model.sectionRanges,
                onLayout: { content, viewport, width in
                    model.reportLayout(contentHeight: content, viewportHeight: viewport, viewportWidth: width)
                },
                onSectionOffsets: { offsets in
                    model.reportSectionOffsets(offsets)
                },
                onUserInteraction: { offset in
                    model.noteUserInteraction(offset: offset)
                },
                onTap: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.showsControls.toggle()
                    }
                },
                onReferenceTap: { url in
                    if let reference = BibleReferenceLink.reference(from: url) {
                        passage = PassageRequest(reference: reference)
                    }
                },
                onScrollRequestHandled: {
                    model.clearPendingScrollRequest()
                }
            )
            .ignoresSafeArea(edges: .bottom)

            // Toques nas bordas: tópico anterior / próximo.
            HStack(spacing: 0) {
                edgeZone(palette) { model.previousSection() }
                Spacer(minLength: 0)
                edgeZone(palette) { model.nextSection() }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if model.preferences.showsProgress {
                    progressBar(palette, model: model)
                }
                Spacer(minLength: 0)
                if let message = model.statusMessage {
                    statusPill(message, palette: palette) {
                        model.resumeAutoScrollNow()
                    }
                    .padding(.bottom, 10)
                }
            }
            .allowsHitTesting(model.statusMessage != nil)

            if model.showsControls {
                controlsOverlay(model, palette: palette)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(model.preferences.hidesSystemInterface)
        .preferredColorScheme(preferredColorScheme(for: model.preferences.theme))
        .persistentSystemOverlays(model.preferences.hidesSystemInterface ? .hidden : .automatic)
        .sheet(isPresented: $showingSettings) {
            PresentationSettingsSheet(model: model)
                .environment(environment)
        }
        .sheet(item: $passage) { request in
            BiblePassagePanel(reference: request.reference)
                .environment(environment)
        }
        .alert("Sair da apresentação?", isPresented: $isExitAlertPresented) {
            Button("Sair", role: .destructive) {
                dismissPresentation(model)
            }
            Button("Continuar", role: .cancel) {}
        } message: {
            Text("O ponto de leitura e as preferências são guardados automaticamente.")
        }
        .task {
            model.prepare()
            environment.screenAwake.setActive(model.preferences.keepsScreenAwake)
            environment.orientation.lockToPortrait(model.preferences.locksPortraitOrientation)
        }
        .onDisappear {
            model.stopAutoScroll()
            environment.screenAwake.releaseIfNeeded()
            environment.orientation.lockToPortrait(false)
            Task { await model.persistState() }
        }
    }

    // MARK: Sobreposições

    private func progressBar(_ palette: PresentationThemeColors, model: PresentationViewModel) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.secondary.opacity(0.18))
                Rectangle()
                    .fill(palette.accent.opacity(0.8))
                    .frame(width: proxy.size.width * model.progress)
            }
        }
        .frame(height: 3)
        .ignoresSafeArea(edges: .top)
    }

    private func statusPill(
        _ message: String,
        palette: PresentationThemeColors,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(message)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(palette.text)
        }
        .buttonStyle(.plain)
    }

    private func controlsOverlay(
        _ model: PresentationViewModel,
        palette: PresentationThemeColors
    ) -> some View {
        VStack {
            topBar(model, palette: palette)
            Spacer()
            bottomBar(model, palette: palette)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(alignment: .top) {
            LinearGradient(
                colors: [palette.background.opacity(0.92), palette.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            .ignoresSafeArea(edges: .top)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [palette.background.opacity(0), palette.background.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .ignoresSafeArea(edges: .bottom)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func topBar(_ model: PresentationViewModel, palette: PresentationThemeColors) -> some View {
        HStack(spacing: 12) {
            Button {
                if model.preferences.confirmsExit {
                    isExitAlertPresented = true
                } else {
                    dismissPresentation(model)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(palette.secondary)
            }
            .accessibilityLabel("Sair da apresentação")

            VStack(alignment: .leading, spacing: 2) {
                Text(model.currentSectionTitle ?? model.speech.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                if model.preferences.showsProgress {
                    Text("Tópico \(model.currentSectionIndex + 1) de \(max(1, model.sectionCount)) · \(model.elapsedDescription)")
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                }
            }

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "textformat.size")
                    .font(.title3)
                    .foregroundStyle(palette.secondary)
            }
            .accessibilityLabel("Ajustes da apresentação")
        }
        .padding(.top, 6)
    }

    private func bottomBar(_ model: PresentationViewModel, palette: PresentationThemeColors) -> some View {
        HStack(spacing: 18) {
            Button {
                model.previousSection()
            } label: {
                Image(systemName: "chevron.up.circle")
                    .font(.title)
            }
            .accessibilityLabel("Tópico anterior")

            Button {
                model.toggleSession()
            } label: {
                Image(systemName: model.session.isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 46))
            }
            .accessibilityLabel(model.session.isRunning ? "Pausar o tempo" : "Iniciar o tempo")

            Button {
                model.nextSection()
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.title)
            }
            .accessibilityLabel("Próximo tópico")

            Spacer()

            Button {
                model.updatePreferences { $0.fontSize = max(PresentationPreferences.fontSizeRange.lowerBound, $0.fontSize - PresentationPreferences.fontSizeStep) }
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.title3)
            }
            .accessibilityLabel("Diminuir o texto")

            Button {
                model.updatePreferences { $0.fontSize = min(PresentationPreferences.fontSizeRange.upperBound, $0.fontSize + PresentationPreferences.fontSizeStep) }
            } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.title3)
            }
            .accessibilityLabel("Aumentar o texto")

            Button {
                model.toggleAutoScroll()
            } label: {
                Image(systemName: model.isAutoScrollEnabled ? "slowmo.circle.fill" : "slowmo.circle")
                    .font(.title2)
            }
            .accessibilityLabel(model.isAutoScrollEnabled ? "Parar a rolagem automática" : "Ligar a rolagem automática")
        }
        .foregroundStyle(palette.text)
        .padding(.bottom, 6)
    }

    private func edgeZone(
        _ palette: PresentationThemeColors,
        action: @escaping () -> Void
    ) -> some View {
        Color.clear
            .frame(width: 34)
            .contentShape(Rectangle())
            .onTapGesture { action() }
            .accessibilityHidden(true)
    }

    // MARK: Ações

    private func load() async {
        do {
            let speech = try await environment.speechRepository.load(id: speechID)
            let model = PresentationViewModel(
                speech: speech,
                repository: environment.speechRepository,
                autosave: environment.makeAutosaveCoordinator()
            )
            model.updatePreferences { preferences in
                // Começa das preferências guardadas no discurso; se o usuário
                // tiver um perfil em uso, ele vale como padrão.
                if preferences == .default {
                    preferences = environment.defaultPresentationPreferences
                }
            }
            self.model = model
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func dismissPresentation(_ model: PresentationViewModel) {
        model.stopAutoScroll()
        dismiss()
    }

    private func preferredColorScheme(for theme: ReadingTheme) -> ColorScheme? {
        switch theme {
        case .system: return nil
        case .light, .sepia: return .light
        case .dark, .highContrast: return .dark
        }
    }
}

/// Cores do tema traduzidas para o SwiftUI.
struct PresentationThemeColors {

    var background: Color
    var text: Color
    var secondary: Color
    var accent: Color
    var cue: Color
    var note: Color

    init(preferences: PresentationPreferences, colorScheme: ColorScheme) {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let palette = PresentationPalette.palette(for: preferences.theme, traits: traits)
        background = Color(uiColor: palette.background)
        text = Color(uiColor: palette.text)
        secondary = Color(uiColor: palette.secondary)
        accent = Color(uiColor: palette.accent)
        cue = Color(uiColor: palette.cue)
        note = Color(uiColor: palette.note)
    }
}
