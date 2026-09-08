import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var fonts: FontLibrary
    @EnvironmentObject var settings: ReaderSettings

    @State private var importing = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(library.books) { book in
                            NavigationLink {
                                ReaderContainer(book: book)
                            } label: {
                                row(book)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { library.books[$0] }.forEach(library.delete)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Cipherbook")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "textformat")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { importing = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { ReaderSettingsView() }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: ImportTypes.epub,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    urls.forEach { library.importEPUB(from: $0) }
                }
            }
            .alert("Import failed",
                   isPresented: Binding(get: { library.lastError != nil },
                                        set: { if !$0 { library.lastError = nil } })) {
                Button("OK", role: .cancel) { library.lastError = nil }
            } message: {
                Text(library.lastError ?? "")
            }
        }
    }

    private func row(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(book.title).font(.headline).lineLimit(2)
            if !book.author.isEmpty {
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
            }
            if book.lastChapter > 0 || book.lastScroll > 0.01 {
                Text("Resuming chapter \(book.lastChapter + 1)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No books yet").font(.title3.weight(.semibold))
            Text("Tap + to import an .epub, or drop files into Cipherbook's folder in the Files app.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Button("Import EPUB") { importing = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
    }
}
