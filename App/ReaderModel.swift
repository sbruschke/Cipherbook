import Foundation
import WebKit
import SwiftUI

@MainActor
final class ReaderModel: NSObject, ObservableObject {
    let webView: WKWebView
    let doc: EPUBDocument
    let stagedFonts: [FontChoice]

    /// Where to put the reader once a chapter has loaded.
    enum Restore: Equatable {
        case word(Int)          // -1: the last word
        case fraction(Double)   // saves from before word positions existed
    }

    @Published var chapter: Int
    @Published var showChrome = true
    /// First word in view (or the word shown, in word mode) and the chapter's word count.
    @Published private(set) var word = 0
    @Published private(set) var wordCount = 0
    /// Current page and page count in page mode; -1 otherwise.
    @Published private(set) var page = -1
    @Published private(set) var pageCount = -1

    var scrollFraction: Double = 0
    private var pendingRestore: Restore?
    private var dualApplied = false
    private var punctApplied = false
    private var settings: ReaderSettings

    init(doc: EPUBDocument, settings: ReaderSettings, stagedFonts: [FontChoice],
         startChapter: Int, startWord: Int?, startScroll: Double) {
        self.doc = doc
        self.settings = settings
        self.stagedFonts = stagedFonts
        self.chapter = min(max(0, startChapter), doc.chapters.count - 1)
        self.scrollFraction = startScroll
        self.word = startWord ?? 0
        self.pendingRestore = startWord.map { .word($0) } ?? .fraction(startScroll)

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        for source in [ReaderRenderer.bootstrapJS, ReaderRenderer.navigationJS] {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
        }
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.allowsBackForwardNavigationGestures = false

        super.init()
        controller.add(self, name: "cb")
        webView.navigationDelegate = self
    }

    func teardown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "cb")
    }

    // MARK: - Fonts

    private func resolve(_ id: String) -> FontChoice {
        if let staged = stagedFonts.first(where: { $0.id == id }) { return staged }
        return FontLibrary.builtIns.first { $0.id == id } ?? .systemDefault
    }

    private var topFont: FontChoice {
        resolve(settings.swapped ? settings.subFontID : settings.mainFontID)
    }

    private var bottomFont: FontChoice {
        resolve(settings.swapped ? settings.mainFontID : settings.subFontID)
    }

    private var currentCSS: String {
        ReaderRenderer.css(settings: settings,
                           top: topFont,
                           bottom: bottomFont,
                           faces: stagedFonts)
    }

    // MARK: - Loading

    func loadCurrentChapter(restoring restore: Restore) {
        guard doc.chapters.indices.contains(chapter) else { return }
        dualApplied = false
        punctApplied = false
        pendingRestore = restore
        let url = doc.chapters[chapter].url
        webView.loadFileURL(url, allowingReadAccessTo: doc.rootDir)
    }

    /// Opens a chapter at its start, or at its last word when stepping back into it.
    func go(to index: Int, atEnd: Bool = false) {
        guard doc.chapters.indices.contains(index) else { return }
        chapter = index
        scrollFraction = atEnd ? 1 : 0
        word = 0
        loadCurrentChapter(restoring: .word(atEnd ? -1 : 0))
    }

    func next() { go(to: chapter + 1) }
    func previous() { go(to: chapter - 1) }

    // MARK: - Settings

    /// Re-applies typography live; a dual-font switch-off needs a fresh document.
    func settingsChanged() {
        // Both a dual-font switch-off and turning it on over already-wrapped
        // punctuation need a fresh document: the two passes only nest correctly
        // when the ruby wrap runs first, which is the order the load path uses.
        if (dualApplied && !settings.dualFont)
            || (settings.dualFont && !dualApplied && punctApplied) {
            loadCurrentChapter(restoring: .word(word))
            return
        }
        applyStyle()
        if settings.dualFont && !dualApplied {
            dualApplied = true
            webView.evaluateJavaScript(ReaderRenderer.dualFontJS, completionHandler: nil)
        }
        applyPunctuationIfNeeded()
        applyMode()
    }

    /// Tells the page which layout to use. Page and word modes turn pages themselves,
    /// so the web view's own scrolling is switched off for them.
    private func applyMode() {
        let mode = settings.readingMode
        webView.scrollView.isScrollEnabled = mode == .scroll
        webView.scrollView.bounces = mode == .scroll
        if mode != .paged { page = -1; pageCount = -1 }
        let config = "{mode:'\(mode.rawValue)',dual:\(settings.dualFont),punct:\(settings.colorPunctuation)}"
        webView.evaluateJavaScript("window.cbSetMode(\(config));", completionHandler: nil)
    }

    /// The wrapping is one-way: switching the tint back off is handled by the
    /// stylesheet, so the spans can stay where they are.
    private func applyPunctuationIfNeeded() {
        guard settings.colorPunctuation, !punctApplied else { return }
        punctApplied = true
        webView.evaluateJavaScript(ReaderRenderer.punctuationJS, completionHandler: nil)
    }

    private func applyStyle() {
        let json = String(data: (try? JSONEncoder().encode(currentCSS)) ?? Data(), encoding: .utf8) ?? "\"\""
        webView.evaluateJavaScript("window.cbSetStyle(\(json));", completionHandler: nil)
    }
}

extension ReaderModel: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [self] in
            applyStyle()
            if settings.dualFont {
                dualApplied = true
                webView.evaluateJavaScript(ReaderRenderer.dualFontJS, completionHandler: nil)
            }
            applyPunctuationIfNeeded()
            applyMode()
            webView.evaluateJavaScript("window.cbInstallBridge();", completionHandler: nil)
            let restore = pendingRestore ?? .word(0)
            pendingRestore = nil
            switch restore {
            case .word(let index):
                // The page waits for its fonts before measuring, so this lands correctly.
                webView.evaluateJavaScript("window.cbRestore(\(index));", completionHandler: nil)
            case .fraction(let f):
                webView.evaluateJavaScript(
                    "window.cbAfterLayout(function(){window.cbScrollTo(\(f));})", completionHandler: nil)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.isFileURL {
            let path = url.standardizedFileURL.path
            Task { @MainActor [self] in
                if let idx = doc.chapters.firstIndex(where: { $0.url.path == path }) {
                    decisionHandler(.cancel)
                    go(to: idx)
                } else {
                    decisionHandler(.allow)
                }
            }
        } else {
            decisionHandler(.cancel)
            Task { @MainActor [self] in UIApplication.shared.open(url) }
        }
    }
}

extension ReaderModel: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        let value = body["value"] as? Double
        let edge = body["value"] as? String
        let numbers = ["word", "words", "page", "pages"].map { (body[$0] as? NSNumber)?.intValue }
        Task { @MainActor [self] in
            switch type {
            case "tap":
                showChrome.toggle()
            case "scroll":
                if let v = value { scrollFraction = v }
            case "position":
                if let w = numbers[0] { word = w }
                if let n = numbers[1] { wordCount = n }
                page = numbers[2] ?? -1
                pageCount = numbers[3] ?? -1
                if wordCount > 0 { scrollFraction = Double(word) / Double(wordCount) }
            case "edge":
                if edge == "next" { go(to: chapter + 1) }
                if edge == "previous" { go(to: chapter - 1, atEnd: true) }
            default:
                break
            }
        }
    }
}

struct ReaderWebView: UIViewRepresentable {
    let model: ReaderModel

    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
