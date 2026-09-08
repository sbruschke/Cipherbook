import SwiftUI
import UniformTypeIdentifiers

@main
struct CipherbookApp: App {
    @StateObject private var library = Library()
    @StateObject private var fonts = FontLibrary()
    @StateObject private var settings = ReaderSettings()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(fonts)
                .environmentObject(settings)
        }
    }
}

enum ImportTypes {
    static let epub: [UTType] = [
        UTType("org.idpf.epub-container"),
        UTType(filenameExtension: "epub")
    ].compactMap { $0 }

    static let font: [UTType] = ([
        UTType("public.truetype-ttf-font"),
        UTType("public.opentype-font"),
        UTType("public.truetype-collection-font"),
        UTType("org.w3.woff")
    ] + ["ttf", "otf", "ttc", "woff", "woff2"].map { UTType(filenameExtension: $0) })
        .compactMap { $0 }
}
