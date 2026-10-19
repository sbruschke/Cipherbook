import SwiftUI
import UIKit
import JournalCore

/// Types onto one parchment page. A transparent text view sits over the page; when the text outgrows
/// the page, `JournalStore.edit` flows the overflow into the next page and editing follows it.
struct EntryEditorView: View {
    @EnvironmentObject var store: JournalStore
    @EnvironmentObject var settings: JournalSettings
    @EnvironmentObject var fonts: FontLibrary
    @Environment(\.dismiss) private var dismiss

    let entryID: String
    @State var pageIndex: Int
    var onDone: () -> Void

    @State private var artText: String?
    @State private var artWork: Task<Void, Never>?

    private static let textBox = CGSize(width: 240 * 0.84, height: 320 * 0.86)

    var body: some View {
        let pages = store.pages(of: entryID)
        let index = min(max(pageIndex, 0), max(pages.count - 1, 0))
        NavigationStack {
            VStack(spacing: 16) {
                if pages.indices.contains(index) {
                    let page = pages[index]
                    ZStack {
                        PageCardView(page: page, hideText: true, artText: artText ?? page.text)
                        PageTextView(pageID: page.id, text: page.text,
                                     font: JournalFonts.ui(settings.mainFontID, size: settings.fontSize, fonts: fonts),
                                     ink: UIColor(Color(hex: settings.effectiveInkHex)),
                                     exclusion: wrapRect(for: page),
                                     onChange: { newText in change(newText, page: page) })
                            .frame(width: Self.textBox.width, height: Self.textBox.height)
                    }
                    .frame(width: PageCardView.nominal.width, height: PageCardView.nominal.height)
                    .padding(.top, 24)
                    HStack(spacing: 28) {
                        Button { pageIndex = index - 1 } label: { Image(systemName: "chevron.left") }
                            .disabled(index == 0)
                        Text("Page \(index + 1) of \(pages.count)").font(.footnote).foregroundStyle(.secondary)
                        Button { pageIndex = index + 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(index >= pages.count - 1)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .onAppear { artText = currentText() }
            .onChange(of: pageIndex) { _ in artText = currentText() }
            .navigationTitle("Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        store.finishEntry(entryID)
                        onDone()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func currentText() -> String? {
        let pages = store.pages(of: entryID)
        return pages.indices.contains(pageIndex) ? pages[pageIndex].text : nil
    }

    /// Text-box points of the doodle's frame when text wraps around it; nil otherwise.
    private func wrapRect(for page: Page) -> CGRect? {
        guard settings.wordArt, settings.wrapAroundArt else { return nil }
        let f = WordArt.placement(seed: page.lookSeedValue).frame
        let w = PageCardView.nominal.width, h = PageCardView.nominal.height
        return CGRect(x: f.minX * w - 0.08 * w, y: f.minY * h - 0.07 * h,
                      width: (f.maxX - f.minX) * w, height: (f.maxY - f.minY) * h)
    }

    private func change(_ newText: String, page: Page) {
        let before = store.pages(of: entryID).count
        let main = JournalFonts.ui(settings.mainFontID, size: settings.fontSize, fonts: fonts)
        let sub = settings.dualFont ? JournalFonts.ui(settings.subFontID, size: settings.fontSize * 0.55, fonts: fonts) : nil
        let ex = wrapRect(for: page)
        store.edit(entryID: entryID, pageIndex: pageIndex, text: newText) { candidate in
            RubyPageText.fits(candidate, main: main, sub: sub, size: Self.textBox, exclusion: ex)
        }
        let after = store.pages(of: entryID).count
        // Typing past the bottom of the last page spills into a new one: follow the cursor there.
        if after > before, pageIndex == before - 1 { pageIndex = after - 1 }
        scheduleArtRefresh(newText)
    }

    /// The doodle is recomputed only after typing pauses, so it doesn't redraw on every keystroke.
    private func scheduleArtRefresh(_ text: String) {
        artWork?.cancel()
        artWork = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.3)) { artText = text }
        }
    }
}

/// A transparent, borderless text view in the journal's font and ink.
struct PageTextView: UIViewRepresentable {
    let pageID: String
    let text: String
    let font: UIFont
    let ink: UIColor
    let exclusion: CGRect?
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.isScrollEnabled = false
        v.clipsToBounds = true
        v.autocorrectionType = .default
        v.delegate = context.coordinator
        DispatchQueue.main.async { v.becomeFirstResponder() }
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        context.coordinator.parent = self
        v.font = font
        v.textColor = ink
        v.tintColor = ink
        v.textContainer.exclusionPaths = exclusion.map { [UIBezierPath(rect: $0)] } ?? []
        if context.coordinator.shownPageID != pageID {
            context.coordinator.shownPageID = pageID
            v.text = text
            v.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        } else if v.text != text {
            // The store reflowed this page (overflow moved on): show its new text, keep the caret at the end.
            v.text = text
            v.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PageTextView
        var shownPageID = ""
        init(_ parent: PageTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.onChange(textView.text) }
    }
}
