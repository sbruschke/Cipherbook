import Foundation

struct EPUBChapter: Identifiable, Hashable {
    let id: Int          // spine index
    let title: String
    let url: URL
}

struct EPUBDocument {
    let rootDir: URL          // extraction root (web view read-access scope)
    let title: String
    let author: String
    let chapters: [EPUBChapter]
}

enum EPUBError: LocalizedError {
    case noContainer
    case noRootfile
    case noSpine

    var errorDescription: String? {
        switch self {
        case .noContainer: return "META-INF/container.xml is missing — not a valid EPUB."
        case .noRootfile:  return "Could not find the OPF package document."
        case .noSpine:     return "The EPUB has no readable spine."
        }
    }
}

/// Minimal, dependency-free EPUB 2/3 package reader.
enum EPUBParser {

    static func parse(rootDir: URL) throws -> EPUBDocument {
        let containerURL = rootDir
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EPUBError.noContainer
        }
        guard let opfRelative = parseContainer(containerURL) else { throw EPUBError.noRootfile }

        let opfURL = rootDir.appendingPathComponent(decode(opfRelative))
        let opfDir = opfURL.deletingLastPathComponent()

        let pkg = parsePackage(opfURL)
        guard !pkg.spine.isEmpty else { throw EPUBError.noSpine }

        // spine idref -> file URL
        var chapters: [EPUBChapter] = []
        var urlToIndex: [String: Int] = [:]
        for idref in pkg.spine {
            guard let href = pkg.manifest[idref]?.href else { continue }
            let url = opfDir.appendingPathComponent(decode(href)).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            urlToIndex[url.path] = chapters.count
            chapters.append(EPUBChapter(id: chapters.count,
                                        title: "Chapter \(chapters.count + 1)",
                                        url: url))
        }
        guard !chapters.isEmpty else { throw EPUBError.noSpine }

        // Titles from the EPUB 3 nav document, falling back to the EPUB 2 NCX.
        var titles: [(String, String)] = []
        if let navItem = pkg.manifest.values.first(where: { $0.properties.contains("nav") }) {
            titles = parseNav(opfDir.appendingPathComponent(decode(navItem.href)))
        }
        if titles.isEmpty, let ncx = pkg.manifest.values.first(where: {
            $0.mediaType == "application/x-dtbncx+xml" || $0.href.lowercased().hasSuffix(".ncx")
        }) {
            titles = parseNCX(opfDir.appendingPathComponent(decode(ncx.href)))
        }
        for (label, href) in titles {
            let clean = decode(href.components(separatedBy: "#")[0])
            guard !clean.isEmpty else { continue }
            let url = opfDir.appendingPathComponent(clean).standardizedFileURL
            if let idx = urlToIndex[url.path], chapters[idx].title.hasPrefix("Chapter ") {
                chapters[idx] = EPUBChapter(id: idx, title: label, url: chapters[idx].url)
            }
        }

        return EPUBDocument(rootDir: rootDir,
                            title: pkg.title.isEmpty ? "Untitled" : pkg.title,
                            author: pkg.author,
                            chapters: chapters)
    }

    private static func decode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    // MARK: - container.xml

    private static func parseContainer(_ url: URL) -> String? {
        let d = XMLCollector(match: { name, attrs in
            name == "rootfile" ? attrs["full-path"] : nil
        })
        d.run(url)
        return d.values.first
    }

    // MARK: - OPF

    struct ManifestItem {
        let href: String
        let mediaType: String
        let properties: String
    }

    struct Package {
        var title = ""
        var author = ""
        var manifest: [String: ManifestItem] = [:]
        var spine: [String] = []
    }

    private static func parsePackage(_ url: URL) -> Package {
        let d = PackageDelegate()
        d.run(url)
        return d.pkg
    }

    private final class PackageDelegate: NSObject, XMLParserDelegate {
        var pkg = Package()
        private var text = ""
        private var capturing: String?

        func run(_ url: URL) {
            guard let parser = XMLParser(contentsOf: url) else { return }
            parser.shouldProcessNamespaces = true
            parser.delegate = self
            parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "item":
                if let id = attributeDict["id"], let href = attributeDict["href"] {
                    pkg.manifest[id] = ManifestItem(href: href,
                                                    mediaType: attributeDict["media-type"] ?? "",
                                                    properties: attributeDict["properties"] ?? "")
                }
            case "itemref":
                if let idref = attributeDict["idref"] { pkg.spine.append(idref) }
            case "title", "creator":
                capturing = elementName
                text = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing != nil { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            guard capturing == elementName else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if elementName == "title", pkg.title.isEmpty { pkg.title = value }
            if elementName == "creator", pkg.author.isEmpty { pkg.author = value }
            capturing = nil
        }
    }

    // MARK: - Navigation

    /// EPUB 3 nav document: ordered `<a href>` links with their label text.
    private static func parseNav(_ url: URL) -> [(String, String)] {
        let d = NavDelegate()
        d.run(url)
        return d.entries
    }

    private final class NavDelegate: NSObject, XMLParserDelegate {
        var entries: [(String, String)] = []
        private var href: String?
        private var text = ""

        func run(_ url: URL) {
            guard let parser = XMLParser(contentsOf: url) else { return }
            parser.shouldProcessNamespaces = true
            parser.delegate = self
            parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            if elementName == "a", let h = attributeDict["href"] {
                href = h
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if href != nil { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            guard elementName == "a", let h = href else { return }
            let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { entries.append((label, h)) }
            href = nil
        }
    }

    /// EPUB 2 NCX: `<navPoint><navLabel><text>…</text></navLabel><content src=…>`
    private static func parseNCX(_ url: URL) -> [(String, String)] {
        let d = NCXDelegate()
        d.run(url)
        return d.entries
    }

    private final class NCXDelegate: NSObject, XMLParserDelegate {
        var entries: [(String, String)] = []
        private var label = ""
        private var text = ""
        private var inText = false

        func run(_ url: URL) {
            guard let parser = XMLParser(contentsOf: url) else { return }
            parser.shouldProcessNamespaces = true
            parser.delegate = self
            parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "text":
                inText = true
                text = ""
            case "content":
                if let src = attributeDict["src"], !label.isEmpty {
                    entries.append((label, src))
                    label = ""
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "text" {
                inText = false
                label = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Generic single-attribute collector used for tiny documents.
    private final class XMLCollector: NSObject, XMLParserDelegate {
        var values: [String] = []
        private let match: (String, [String: String]) -> String?

        init(match: @escaping (String, [String: String]) -> String?) {
            self.match = match
        }

        func run(_ url: URL) {
            guard let parser = XMLParser(contentsOf: url) else { return }
            parser.shouldProcessNamespaces = true
            parser.delegate = self
            parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            if let v = match(elementName, attributeDict) { values.append(v) }
        }
    }
}
