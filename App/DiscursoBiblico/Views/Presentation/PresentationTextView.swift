//
//  PresentationTextView.swift
//  DiscursoBiblico
//
//  Ponte com o UIKit para o texto da apresentação.
//
//  Por que `UITextView`: a rolagem automática precisa de deslocamento em
//  pontos, sincronizado com o `AutoScrollEngine` do núcleo. Com o TextKit 1
//  (pilha `NSTextStorage` → `NSLayoutManager` → `NSTextContainer` montada em
//  `PresentationScrollTextView.makeTextView()`) também conseguimos medir
//  exatamente onde cada tópico começa — usado para "tópico atual" e para
//  pular de tópico.
//
//  Regras de interação:
//   - toque simples: mostra/oculta os controles e pausa a rolagem;
//   - arrasto: rola manualmente e pausa a rolagem;
//   - toque em referência bíblica: abre o painel (sem perder a posição).
//

import DiscursoCore
import SwiftUI
import UIKit

struct PresentationTextView: UIViewRepresentable {

    var attributedText: NSAttributedString
    var horizontalInset: CGFloat
    var targetOffset: CGFloat
    var pendingScrollToSection: Int?
    var sectionRanges: [NSRange]

    var onLayout: (CGFloat, CGFloat, CGFloat) -> Void
    var onSectionOffsets: ([Int: CGFloat]) -> Void
    var onUserInteraction: (CGFloat) -> Void
    var onTap: () -> Void
    var onReferenceTap: (URL) -> Void
    var onScrollRequestHandled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PresentationScrollTextView {
        let textView = PresentationScrollTextView.makeTextView()
        textView.delegate = context.coordinator
        context.coordinator.attach(textView)
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = false
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 120, right: 20)
        textView.backgroundColor = .clear
        textView.dataDetectorTypes = []
        textView.onLayoutPass = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.measure(textView)
        }

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)

        return textView
    }

    func updateUIView(_ textView: PresentationScrollTextView, context: Context) {
        context.coordinator.parent = self
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(
            top: 24,
            left: max(8, horizontalInset),
            bottom: 120,
            right: max(8, horizontalInset)
        )

        if context.coordinator.appliedText !== attributedText {
            context.coordinator.appliedText = attributedText
            let offset = textView.contentOffset
            textView.attributedText = attributedText
            textView.setContentOffset(offset, animated: false)
            textView.setNeedsLayout()
        }

        if let request = pendingScrollToSection,
           request != context.coordinator.handledScrollRequest {
            context.coordinator.handledScrollRequest = request
            context.coordinator.scroll(to: request, in: textView)
            onScrollRequestHandled()
        }

        context.coordinator.apply(offset: targetOffset, in: textView)
    }

    // MARK: - Coordenação

    final class Coordinator: NSObject, UITextViewDelegate {

        var parent: PresentationTextView
        var appliedText: NSAttributedString?
        var handledScrollRequest: Int?
        var isApplyingProgrammatic = false
        var isUserInteracting = false

        private weak var textView: UITextView?
        private var lastLayoutSignature = ""
        private var measuredOffsets: [Int: CGFloat] = [:]

        init(parent: PresentationTextView) {
            self.parent = parent
        }

        /// Ligação feita pelo `PresentationScrollTextView` ao ser criado.
        func attach(_ textView: UITextView) {
            self.textView = textView
        }

        // MARK: Rolagem

        func apply(offset: CGFloat, in textView: UITextView) {
            guard !isUserInteracting else { return }
            let maximum = max(0, textView.contentSize.height - textView.bounds.height)
            let desired = min(max(0, offset), maximum)
            guard abs(textView.contentOffset.y - desired) > 0.5 else { return }
            isApplyingProgrammatic = true
            textView.setContentOffset(CGPoint(x: 0, y: desired), animated: false)
            isApplyingProgrammatic = false
        }

        func scroll(to sectionIndex: Int, in textView: UITextView) {
            guard let y = measuredOffsets[sectionIndex] else { return }
            let maximum = max(0, textView.contentSize.height - textView.bounds.height)
            let desired = min(max(0, y - 12), maximum)
            isApplyingProgrammatic = true
            textView.setContentOffset(CGPoint(x: 0, y: desired), animated: true)
            isApplyingProgrammatic = false
        }

        // MARK: Medição

        func measure(_ textView: UITextView) {
            let signature = "\(Int(textView.bounds.width))x\(Int(textView.contentSize.height))x\(parent.sectionRanges.count)"
            guard signature != lastLayoutSignature else {
                parent.onLayout(textView.contentSize.height, textView.bounds.height, textView.bounds.width)
                return
            }
            lastLayoutSignature = signature

            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer
            layoutManager.ensureLayout(for: textContainer)

            let origin = CGPoint(
                x: textView.textContainerInset.left + textView.textContainer.lineFragmentPadding,
                y: textView.textContainerInset.top
            )
            let textLength = textView.attributedText?.length ?? 0
            var offsets: [Int: CGFloat] = [:]
            for (index, range) in parent.sectionRanges.enumerated() {
                guard range.length > 0, range.location + range.length <= textLength else { continue }
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                offsets[index] = rect.minY + origin.y
            }
            measuredOffsets = offsets
            parent.onSectionOffsets(offsets)
            parent.onLayout(textView.contentSize.height, textView.bounds.height, textView.bounds.width)
        }

        // MARK: UITextViewDelegate

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserInteracting = true
            parent.onUserInteraction(scrollView.contentOffset.y)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                isUserInteracting = false
                parent.onUserInteraction(scrollView.contentOffset.y)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserInteracting = false
            parent.onUserInteraction(scrollView.contentOffset.y)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard isUserInteracting, !isApplyingProgrammatic else { return }
            parent.onUserInteraction(scrollView.contentOffset.y)
        }

        @objc func handleTap() {
            parent.onUserInteraction(textView?.contentOffset.y ?? 0)
            parent.onTap()
        }

        // Referências como ligações internas (iOS 17+).
        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case .link(let url) = textItem.content else { return defaultAction }
            if url.scheme == BibleReferenceLink.scheme {
                return UIAction { [weak self] _ in
                    self?.parent.onReferenceTap(url)
                }
            }
            return UIAction { _ in
                UIApplication.shared.open(url)
            }
        }
    }
}

/// `UITextView` que avisa quando precisa medir de novo (largura mudou etc.).
final class PresentationScrollTextView: UITextView {

    var onLayoutPass: (() -> Void)?

    /// Cria a instância **sempre com TextKit 1**.
    ///
    /// No iOS 16+ o `UITextView(frame:)` usa TextKit 2 por padrão, cujo
    /// `textLayoutManager` não oferece `boundingRect(forGlyphRange:in:)` — a
    /// medição das posições de tópico depende do `NSLayoutManager`. Iniciar com
    /// uma pilha TextKit 1 própria (storage → layout manager → container) fixa
    /// o caminho antigo, que é o que o `Coordinator` mede.
    static func makeTextView() -> PresentationScrollTextView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        return PresentationScrollTextView(frame: .zero, textContainer: container)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutPass?()
    }
}
