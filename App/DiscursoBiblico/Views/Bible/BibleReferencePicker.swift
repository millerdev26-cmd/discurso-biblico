//
//  BibleReferencePicker.swift
//  DiscursoBiblico
//
//  Escolha de uma referência bíblica: livro, capítulo e versículos.
//
//  O catálogo de livros vem do núcleo (`BibleBookCatalog`), o mesmo usado no
//  reconhecimento automático de referências no texto.
//

import DiscursoCore
import SwiftUI

struct BibleReferencePicker: View {

    @Environment(\.dismiss) private var dismiss

    let onSelect: (BibleReference) -> Void

    @State private var bookID: BibleBookID
    @State private var chapter: Int
    @State private var includesVerses: Bool
    @State private var verseStart: Int
    @State private var verseEnd: Int

    init(initial: BibleReference? = nil, onSelect: @escaping (BibleReference) -> Void) {
        self.onSelect = onSelect
        let reference = initial ?? BibleReference(bookID: .john, chapter: 3, verseStart: 16, verseEnd: 16)
        let firstPart = reference.parts.first
        let firstRange = firstPart?.verses.first
        _bookID = State(initialValue: reference.bookID)
        _chapter = State(initialValue: reference.primaryChapter)
        _includesVerses = State(initialValue: firstPart.map { !$0.isWholeChapter } ?? false)
        _verseStart = State(initialValue: firstRange?.start ?? 1)
        _verseEnd = State(initialValue: firstRange?.end ?? firstRange?.start ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Livro", selection: $bookID) {
                        ForEach(BibleBookCatalog.allBooks, id: \.id) { book in
                            Text("\(book.ordinal). \(book.name)").tag(book.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: bookID) { _, _ in
                        chapter = min(max(chapter, 1), max(1, maxChapter))
                    }

                    Stepper(value: $chapter, in: 1...max(1, maxChapter)) {
                        Text("Capítulo \(chapter)")
                    }
                } header: {
                    Text("Livro e capítulo")
                } footer: {
                    if maxChapter > 0 {
                        Text("\(bookName) tem \(maxChapter) capítulo(s).")
                    }
                }

                Section {
                    Toggle("Versículos específicos", isOn: $includesVerses)
                    if includesVerses {
                        Stepper(value: $verseStart, in: 1...200) {
                            Text("Do versículo \(verseStart)")
                        }
                        .onChange(of: verseStart) { _, newValue in
                            if verseEnd < newValue { verseEnd = newValue }
                        }

                        Stepper(value: $verseEnd, in: verseStart...200) {
                            Text("Até o versículo \(verseEnd)")
                        }
                    }
                } header: {
                    Text("Versículos")
                } footer: {
                    Text("Sem versículos marcados, a referência aponta o capítulo inteiro.")
                }

                Section {
                    HStack {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reference.displayText)
                                .font(.headline)
                            Text(reference.summarizedText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if reference.isValid() {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("Prévia")
                } footer: {
                    Text("O texto bíblico em si é consultado na fonte oficial; o aplicativo não armazena traduções.")
                }
            }
            .navigationTitle("Referência bíblica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Usar") {
                        onSelect(reference)
                        dismiss()
                    }
                    .disabled(!reference.isValid())
                }
            }
        }
    }

    // MARK: Apoio

    private var reference: BibleReference {
        if includesVerses {
            let start = max(1, verseStart)
            let end = max(start, verseEnd)
            return BibleReference(bookID: bookID, chapter: chapter, verseStart: start, verseEnd: end)
        }
        return BibleReference(bookID: bookID, chapter: chapter)
    }

    private var bookName: String {
        BibleBookCatalog.displayName(for: bookID)
    }

    private var maxChapter: Int {
        BibleBookCatalog.chapterCount(of: bookID)
    }
}

#Preview {
    BibleReferencePicker { reference in
        print(reference.displayText)
    }
}
