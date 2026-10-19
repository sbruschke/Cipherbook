import SwiftUI
import UIKit
import JournalCore

/// Types onto one parchment page. A transparent text view sits over the page; when the text outgrows
/// the page, `JournalStore.edit` flows the overflow into the next page and editing follows it.
///
/// While typing, the text view owns its text: SwiftUI never writes into it except on a page change or
/// when the store reflowed this page (`ForcedText`). Re-applying state on every keystroke is what used
/// to send the caret back to the start.
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
    @State private var forced: ForcedText?
    @State private var forceCounter = 0

    var body: some View {
        let pages = store.pages(of: entryID)
        let index = min(max(pageIndex, 0), max(pages.count - 1, 0))
        NavigationStack {
            VStack(spacing: 16) {
                if pages.indices.contains(index) {
                    let page = pages[index]
                    let look = PageLook.make(seed: page.lookSeedValue, preset: settings.preset)
                    let box = textBox(for: look)
                    ZStack {
                        PageCardView(page: page, hideText: true, artText: artText ?? page.text)
                        PageTextView(pageID: page.id, text: page.text, forced: forced,
                                     font: JournalFonts.ui(settings.mainFontID, size: settings.fontSize, fonts: fonts),
                                     ink: UIColor(Color(hex: settings.effectiveInkHex)),
                                     exclusion: wrapRect(for: page, look: look),
                                     onChange: { newText, atEnd in change(newText, atEnd: atEnd, page: page, look: look) })
                            .frame(width: box.width, height: box.height)
                            .rotationEffect(.degrees(look.rotation))     // sits on the paper like the finished text
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

    /// The text area exactly as the finished page draws it: 84 % x 86 % of this page's own width and height.
    private func textBox(for look: PageLook) -> CGSize {
        CGSize(width: PageCardView.nominal.width * look.widthScale * 0.84, height: PageCardView.nominal.height * 0.86)
    }

    private func currentText() -> String? {
        let pages = store.pages(of: entryID)
        return pages.indices.contains(pageIndex) ? pages[pageIndex].text : nil
    }

    /// Text-box points of the doodle's frame when text wraps around it; nil otherwise.
    private func wrapRect(for page: Page, look: PageLook) -> CGRect? {
        guard settings.wordArt, settings.wrapAroundArt else { return nil }
        let f = WordArt.placement(seed: page.lookSeedValue).frame
        let w = PageCardView.nominal.width * look.widthScale, h = PageCardView.nominal.height
        return CGRect(x: f.minX * w - 0.08 * w, y: f.minY * h - 0.07 * h,
                      width: (f.maxX - f.minX) * w, height: (f.maxY - f.minY) * h)
    }

    private func change(_ newText: String, atEnd: Bool, page: Page, look: PageLook) {
        let before = store.pages(of: entryID).count
        let main = JournalFonts.ui(settings.mainFontID, size: settings.fontSize, fonts: fonts)
        let sub = settings.dualFont ? JournalFonts.ui(settings.subFontID, size: settings.fontSize * 0.55, fonts: fonts) : nil
        let box = textBox(for: look)
        let ex = wrapRect(for: page, look: look)
        let editedIndex = pageIndex
        store.edit(entryID: entryID, pageIndex: editedIndex, text: newText) { candidate in
            // Fit for both engines: CoreText (how the finished page is drawn) and TextKit (what this text
            // view shows), so text never runs past the bottom of the paper while it is being typed.
            RubyPageText.fits(candidate, main: main, sub: sub, size: box, exclusion: ex)
                && Self.textKitHeight(candidate, font: main, width: box.width) <= box.height
        }
        let pagesNow = store.pages(of: entryID)
        // If the store reflowed this page (words moved to or from a neighbour), the text view must show it.
        if pagesNow.indices.contains(editedIndex), pagesNow[editedIndex].text != newText {
            forceCounter += 1
            forced = ForcedText(n: forceCounter, text: pagesNow[editedIndex].text)
        }
        // Typing past the bottom of the last page spills into a new one: follow the cursor there.
        if atEnd, pagesNow.count > before, editedIndex == before - 1 { pageIndex = pagesNow.count - 1 }
        scheduleArtRefresh(newText)
    }

    private static func textKitHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let rect = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(rect.height)
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

/// An instruction to replace the text view's text (the store reflowed the page being edited).
struct ForcedText: Equatable {
    let n: Int
    let text: String
}

/// A transparent, borderless text view in the journal's font and ink.
struct PageTextView: UIViewRepresentable {
    let pageID: String
    let text: String               // read only when the page changes
    let forced: ForcedText?
    let font: UIFont
    let ink: UIColor
    let exclusion: CGRect?
    let onChange: (String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        // A non-scrolling text view reports its content height as its size, so SwiftUI let it grow past
        // the page as you typed. Scrolling on + a pinned size keeps it exactly the page's text area.
        v.isScrollEnabled = true
        v.alwaysBounceVertical = false
        v.showsVerticalScrollIndicator = false
        v.contentInsetAdjustmentBehavior = .never
        v.clipsToBounds = true
        v.autocorrectionType = .default
        v.delegate = context.coordinator
        DispatchQueue.main.async { v.becomeFirstResponder() }
        return v
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }

    func updateUIView(_ v: UITextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        // Assigning these re-applies attributes to the whole text and moves the caret: only on a real change.
        if v.font != font { v.font = font }
        if v.textColor != ink { v.textColor = ink }
        if v.tintColor != ink { v.tintColor = ink }
        if c.exclusion != exclusion {
            c.exclusion = exclusion
            v.textContainer.exclusionPaths = exclusion.map { [UIBezierPath(rect: $0)] } ?? []
        }
        if c.shownPageID != pageID {
            // A different page: load its text and put the caret at the end.
            c.shownPageID = pageID
            c.appliedForce = forced?.n ?? c.appliedForce
            v.text = text
            v.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        } else if let f = forced, f.n != c.appliedForce {
            // The store reflowed this page: show its text, keep the caret where the user was typing.
            c.appliedForce = f.n
            let caret = v.selectedRange.location
            v.text = f.text
            v.selectedRange = NSRange(location: min(caret, (f.text as NSString).length), length: 0)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PageTextView
        var shownPageID = ""
        var appliedForce = 0
        var exclusion: CGRect?
        init(_ parent: PageTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            let len = (textView.text as NSString).length
            parent.onChange(textView.text, textView.selectedRange.location >= len)
        }
    }
}
