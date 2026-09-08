import SwiftUI

struct ReaderContainer: View {
    let book: Book
    @EnvironmentObject var library: Library
    @EnvironmentObject var fonts: FontLibrary
    @EnvironmentObject var settings: ReaderSettings

    @State private var model: ReaderModel?
    @State private var error: String?

    var body: some View {
        Group {
            if let model {
                ReaderScreen(model: model, book: book)
            } else if let error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(error).multilineTextAlignment(.center).padding(.horizontal, 32)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .onAppear(perform: build)
    }

    private func build() {
        guard model == nil else { return }
        do {
            let doc = try EPUBParser.parse(rootDir: book.contentDir)
            let staged = fonts.stageFonts(into: book.contentDir)
            let m = ReaderModel(doc: doc,
                                settings: settings,
                                stagedFonts: staged,
                                startChapter: book.lastChapter,
                                startScroll: book.lastScroll)
            model = m
            m.loadCurrentChapter(restoring: book.lastScroll)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ReaderScreen: View {
    @ObservedObject var model: ReaderModel
    let book: Book

    @EnvironmentObject var library: Library
    @EnvironmentObject var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showSettings = false
    @State private var showChapters = false

    private var styleToken: String {
        [settings.mainFontID, settings.subFontID,
         String(settings.fontSize), String(settings.subScale),
         String(settings.lineHeight), String(settings.margin),
         String(settings.letterSpacing), String(settings.justified),
         String(settings.dualFont), String(settings.swapped),
         settings.theme.rawValue].joined(separator: "|")
    }

    var body: some View {
        ZStack(alignment: .top) {
            settings.theme.uiBackground.ignoresSafeArea()
            ReaderWebView(model: model).ignoresSafeArea(edges: .bottom)

            if model.showChrome {
                topBar.transition(.move(edge: .top).combined(with: .opacity))
                VStack { Spacer(); bottomBar }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.showChrome)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!model.showChrome)
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .onChange(of: styleToken) { _ in model.settingsChanged() }
        .onChange(of: model.chapter) { _ in persist() }
        .onDisappear {
            persist()
            model.teardown()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { ReaderSettingsView() }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChapters) { chapterList }
    }

    private func persist() {
        var updated = book
        updated.lastChapter = model.chapter
        updated.lastScroll = model.scrollFraction
        library.save(updated)
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Button { persist(); dismiss() } label: {
                Image(systemName: "chevron.left")
            }
            Text(model.doc.chapters.indices.contains(model.chapter)
                 ? model.doc.chapters[model.chapter].title : model.doc.title)
                .font(.footnote).lineLimit(1).frame(maxWidth: .infinity)
            Button { showChapters = true } label: { Image(systemName: "list.bullet") }
            Button { settings.dualFont.toggle() } label: {
                Image(systemName: settings.dualFont ? "textformat.abc.dottedunderline" : "textformat.abc")
            }
            Button { showSettings = true } label: { Image(systemName: "textformat.size") }
        }
        .font(.system(size: 17, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var bottomBar: some View {
        HStack {
            Button { model.previous() } label: { Image(systemName: "chevron.left.circle") }
                .disabled(model.chapter == 0)
            Spacer()
            Text("\(model.chapter + 1) / \(model.doc.chapters.count)")
                .font(.footnote.monospacedDigit())
            Spacer()
            Button { model.next() } label: { Image(systemName: "chevron.right.circle") }
                .disabled(model.chapter >= model.doc.chapters.count - 1)
        }
        .font(.system(size: 22))
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.regularMaterial)
    }

    private var chapterList: some View {
        NavigationStack {
            List(model.doc.chapters) { chapter in
                Button {
                    model.go(to: chapter.id)
                    showChapters = false
                } label: {
                    HStack {
                        Text(chapter.title).lineLimit(2)
                        Spacer()
                        if chapter.id == model.chapter {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showChapters = false }
                }
            }
        }
    }
}
