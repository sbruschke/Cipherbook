import Foundation
import WebKit
import SwiftUI

@MainActor
final class ReaderModel: NSObject, ObservableObject {
    let webView: WKWebView
    let doc: EPUBDocument
    let stagedFonts: [FontChoice]

    @Published var chapter: Int
    @Published var showChrome = true

    var scrollFraction: Double = 0
    private var pendingRestore: Double?
    private var dualApplied = false
    private var settings: ReaderSettings

    init(doc: EPUBDocument, settings: ReaderSettings, stagedFonts: [FontChoice],
         startChapter: Int, startScroll: Double) {
        self.doc = doc
        self.settings = settings
        self.stagedFonts = stagedFonts
        self.chapter = min(max(0, startChapter), doc.chapters.count - 1)
        self.scrollFraction = startScroll
        self.pendingRestore = startScroll

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: ReaderRenderer.bootstrapJS,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
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

    func loadCurrentChapter(restoring fraction: Double? = nil) {
        guard doc.chapters.indices.contains(chapter) else { return }
        dualApplied = false
        pendingRestore = fraction
        let url = doc.chapters[chapter].url
        webView.loadFileURL(url, allowingReadAccessTo: doc.rootDir)
    }

    func go(to index: Int) {
        guard doc.chapters.indices.contains(index) else { return }
        chapter = index
        scrollFraction = 0
        loadCurrentChapter(restoring: 0)
    }

    func next() { go(to: chapter + 1) }
    func previous() { go(to: chapter - 1) }

    // MARK: - Settings

    /// Re-applies typography live; a dual-font switch-off needs a fresh document.
    func settingsChanged() {
        if dualApplied && !settings.dualFont {
            loadCurrentChapter(restoring: scrollFraction)
            return
        }
        applyStyle()
        if settings.dualFont && !dualApplied {
            dualApplied = true
            webView.evaluateJavaScript(ReaderRenderer.dualFontJS, completionHandler: nil)
        }
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
            webView.evaluateJavaScript(ReaderRenderer.bridgeJS, completionHandler: nil)
            let restore = pendingRestore
            pendingRestore = nil
            if let f = restore, f > 0 {
                // Give the layout (and any freshly-loaded webfont) a beat to settle.
                try? await Task.sleep(nanoseconds: 350_000_000)
                webView.evaluateJavaScript("window.cbScrollTo(\(f));", completionHandler: nil)
            } else {
                webView.evaluateJavaScript("window.scrollTo(0,0);", completionHandler: nil)
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
        Task { @MainActor [self] in
            switch type {
            case "tap": showChrome.toggle()
            case "scroll": if let v = value { scrollFraction = v }
            default: break
            }
        }
    }
}

struct ReaderWebView: UIViewRepresentable {
    let model: ReaderModel

    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
