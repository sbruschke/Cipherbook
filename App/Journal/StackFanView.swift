import SwiftUI
import JournalCore

/// A stack laid out as a physical pile. Slide the top page sideways and it goes to the bottom, revealing
/// the next one; the move is physical — the page slides out from the top, drops behind the pile while
/// clear of it, and slides back in underneath.
struct StackFanView: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    let entryID: String
    var onEdit: (Int) -> Void

    private static let clearance: CGFloat = 270        // a page width plus the pile's jitter
    private static let duration = 1.1

    private struct Shuffle {
        let from: Int, to: Int
        let path: [ShuffleKeyframe]
        let startDrag: CGFloat      // where the finger left the page (signed)
        let dir: CGFloat            // +1 slides out to the right, -1 to the left
    }

    @State private var shuffle: Shuffle?
    @State private var progress = 0.0
    @State private var dragX: CGFloat = 0        // live drag of the top page, signed

    var body: some View {
        let pages = store.pages(of: entryID)
        let top = pages.count - 1
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            ZStack {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                    let s = state(for: i, count: pages.count)
                    PageCardView(page: page, lift: s.lift)
                        .offset(x: s.offsetX + jitter(page).width, y: jitter(page).height)
                        .zIndex(s.z)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if shuffle == nil, top >= 0 { onEdit(top) } }
            .gesture(slide(count: pages.count))
            .contextMenu {
                if pages.count > 1 {
                    Button("Send this page to the back") { play(from: top, to: 0, count: pages.count, dir: 1) }
                    Button("Bring the bottom page to the front") { play(from: 0, to: top, count: pages.count, dir: 1) }
                }
                if top >= 0 { Button("Edit this page") { onEdit(top) } }
            }
            VStack {
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .padding()
                Spacer()
                Text(pages.count > 1 ? "Slide the top page aside to turn to the next · tap to write"
                                     : "Tap the page to write")
                    .font(.caption).foregroundColor(.white.opacity(0.7)).padding(.bottom, 12)
            }
        }
    }

    // MARK: per-page state

    private struct PageState { var offsetX: CGFloat; var lift: Double; var z: Double }

    private func state(for i: Int, count: Int) -> PageState {
        if let sh = shuffle {
            let kf = StackOps.sample(sh.path, at: progress)
            if i == sh.from {
                // Ease from where the finger let go into the scripted slide-out.
                let carried = abs(sh.startDrag) * CGFloat(max(0, 1 - progress / 0.3))
                let slide = max(CGFloat(kf.offsetX), carried) * sh.dir
                return PageState(offsetX: slide, lift: kf.lift, z: Double(kf.layer) + 0.5)
            }
            // The others close up around the moving page: their rank among the rest, shifted past its layer.
            let rank = i < sh.from ? i : i - 1
            return PageState(offsetX: 0, lift: 0, z: Double(rank < kf.layer ? rank : rank + 1))
        }
        if i == count - 1 { return PageState(offsetX: dragX, lift: dragX == 0 ? 0 : 0.5, z: Double(i)) }
        return PageState(offsetX: 0, lift: 0, z: Double(i))
    }

    private func jitter(_ p: Page) -> CGSize {
        var g = SplitMix64(seed: deriveSeed(p.lookSeedValue, 31))
        return CGSize(width: g.range(-5, 5), height: g.range(-5, 5))
    }

    // MARK: gesture and playback

    /// Sliding anywhere on the pile moves the top page (the only one a finger can actually reach).
    private func slide(count: Int) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                guard shuffle == nil, abs(v.translation.width) > abs(v.translation.height) else { return }
                dragX = v.translation.width
            }
            .onEnded { v in
                guard shuffle == nil else { return }
                let released = dragX
                dragX = 0
                if count > 1, let dir = PageTurn.direction(dx: Double(v.translation.width), dy: Double(v.translation.height),
                                                           predictedDx: Double(v.predictedEndTranslation.width)) {
                    play(from: count - 1, to: 0, count: count, startDrag: released, dir: CGFloat(dir))
                }
            }
    }

    private func play(from: Int, to: Int, count: Int, startDrag: CGFloat = 0, dir: CGFloat) {
        guard shuffle == nil, from != to, (0..<count).contains(from), (0..<count).contains(to) else { return }
        let path = StackOps.shufflePath(count: count, from: from, to: to, clearance: Double(Self.clearance))
        guard !path.isEmpty else { return }
        progress = 0
        shuffle = Shuffle(from: from, to: to, path: path, startDrag: startDrag, dir: dir)
        Task { @MainActor in
            let start = Date()
            while true {
                let t = min(1, Date().timeIntervalSince(start) / Self.duration)
                progress = t
                if t >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            store.reorder(entryID: entryID, from: from, to: to)
            shuffle = nil
            progress = 0
        }
    }
}
