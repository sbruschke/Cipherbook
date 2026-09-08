import Foundation
import ZIPFoundation

struct Book: Identifiable, Codable, Hashable {
    var id: String            // folder name under Books/
    var title: String
    var author: String
    var addedAt: Date
    var lastChapter: Int = 0
    var lastScroll: Double = 0    // 0...1 fraction within the chapter

    var dir: URL { Storage.booksDir.appendingPathComponent(id, isDirectory: true) }
    var contentDir: URL { dir.appendingPathComponent("content", isDirectory: true) }
    var metaURL: URL { dir.appendingPathComponent("meta.json") }
}

@MainActor
final class Library: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var lastError: String?

    init() { reload() }

    func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Storage.booksDir,
                                                includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        books = dirs.compactMap { dir -> Book? in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")) else {
                return nil
            }
            return try? decoder.decode(Book.self, from: data)
        }
        .sorted { $0.addedAt > $1.addedAt }
    }

    func save(_ book: Book) {
        if let idx = books.firstIndex(where: { $0.id == book.id }) { books[idx] = book }
        guard let data = try? JSONEncoder().encode(book) else { return }
        try? data.write(to: book.metaURL, options: .atomic)
    }

    func delete(_ book: Book) {
        try? FileManager.default.removeItem(at: book.dir)
        books.removeAll { $0.id == book.id }
    }

    /// Copies + extracts an .epub picked from the Files app.
    @discardableResult
    func importEPUB(from source: URL) -> Book? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let id = UUID().uuidString
        let dir = Storage.booksDir.appendingPathComponent(id, isDirectory: true)
        let content = dir.appendingPathComponent("content", isDirectory: true)

        do {
            try fm.createDirectory(at: content, withIntermediateDirectories: true)
            // Copy first: unzipping straight from an iCloud/provider URL is unreliable.
            let staged = dir.appendingPathComponent("book.epub")
            try fm.copyItem(at: source, to: staged)
            try fm.unzipItem(at: staged, to: content)
            try? fm.removeItem(at: staged)

            let doc = try EPUBParser.parse(rootDir: content)
            let book = Book(id: id,
                            title: doc.title,
                            author: doc.author,
                            addedAt: Date())
            save(book)
            books.insert(book, at: 0)
            return book
        } catch {
            try? fm.removeItem(at: dir)
            lastError = "Couldn't import \(source.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }
}
