import SwiftUI
import JournalCore

/// A stack laid out as a physical pile. Pages keep their height order; moving one slides it out from
/// under the pages above it, lifts it clear, carries it across and lowers it at its new height.
struct StackFanView: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    let entryID: String
    var onEdit: (Int) -> Void

    private static let clearance: CGFloat = 270        // a page width plus the pile's jitter
    private static let duration = 1.3

    private struct Shuffle {
        let from: Int, to: Int
        let path: [ShuffleKeyframe]
        let startDrag: CGFloat
    }

    @State private var shuffle: Shuffle?
    @State private var progress = 0.0
    @State private var dragIndex: Int?
    @State private var dragX: CGFloat = 0

    var body: some View {
        let pages = store.pages(of: entryID)
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            ZStack {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                    let s = state(for: i, count: pages.count)
                    PageCardView(page: page, lift: s.lift)
                        .offset(x: s.offsetX + jitter(page).width, y: jitter(page).height)
                        .zIndex(s.z)
                        .onTapGesture { if shuffle == nil { onEdit(i) } }
                        .gesture(pullOut(i, count: pages.count))
                        .contextMenu {
                            Button("Bring to front") { play(from: i, to: pages.count - 1, count: pages.count) }
                                .disabled(i == pages.count - 1)
                            Button("Send to back") { play(from: i, to: 0, count: pages.count) }
                                .disabled(i == 0)
                            Button("Move up") { play(from: i, to: i + 1, count: pages.count) }
                                .disabled(i == pages.count - 1)
                            Button("Move down") { play(from: i, to: i - 1, count: pages.count) }
                                .disabled(i == 0)
                            Button("Edit this page") { onEdit(i) }
                        }
                }
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
                Text("Drag a page sideways to pull it out · press and hold for more")
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
                let slide = max(CGFloat(kf.offsetX), sh.startDrag * CGFloat(max(0, 1 - progress / 0.3)))
                return PageState(offsetX: slide, lift: kf.lift, z: Double(kf.layer) + 0.5)
            }
            // The others close up around the moving page: their rank among the rest, shifted past its layer.
            let rank = i < sh.from ? i : i - 1
            return PageState(offsetX: 0, lift: 0, z: Double(rank < kf.layer ? rank : rank + 1))
        }
        if dragIndex == i { return PageState(offsetX: dragX, lift: 0.4, z: Double(i) + 0.5) }
        return PageState(offsetX: 0, lift: 0, z: Double(i))
    }

    private func jitter(_ p: Page) -> CGSize {
        var g = SplitMix64(seed: deriveSeed(p.lookSeedValue, 31))
        return CGSize(width: g.range(-5, 5), height: g.range(-5, 5))
    }

    // MARK: gestures and playback

    private func pullOut(_ i: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                guard shuffle == nil else { return }
                dragIndex = i
                dragX = max(0, v.translation.width)
            }
            .onEnded { v in
                guard shuffle == nil else { return }
                let released = max(0, v.translation.width)
                dragIndex = nil; dragX = 0
                if released > Self.clearance * 0.5, i < count - 1 {
                    play(from: i, to: count - 1, count: count, startDrag: released)
                }
            }
    }

    private func play(from: Int, to: Int, count: Int, startDrag: CGFloat = 0) {
        guard shuffle == nil, from != to, (0..<count).contains(to) else { return }
        let path = StackOps.shufflePath(count: count, from: from, to: to, clearance: Double(Self.clearance))
        guard !path.isEmpty else { return }
        progress = 0
        shuffle = Shuffle(from: from, to: to, path: path, startDrag: startDrag)
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
