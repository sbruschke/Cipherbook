import SwiftUI
import JournalCore

/// The wall: a pannable, zoomable canvas of page stacks at their stored positions.
struct WallView: View {
    @EnvironmentObject var store: JournalStore
    @EnvironmentObject var settings: JournalSettings
    @Binding var zoom: CGFloat
    var onOpen: (String) -> Void
    var onMenu: (String) -> Void

    @State private var pan = CGSize.zero
    @GestureState private var panDelta = CGSize.zero
    @GestureState private var zoomDelta: CGFloat = 1
    @State private var draggingID: String?
    @State private var dragOffset = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: settings.preset == .slate ? "#cfc9bb" : "#3a3228")
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(panGesture())
                    .simultaneousGesture(magnifyGesture())

                ZStack {
                    ForEach(store.liveEntries) { e in
                        let lifted = draggingID == e.id
                        StackThumb(entry: e, pages: store.pages(of: e.id), lifted: lifted)
                            .offset(x: e.x + (lifted ? dragOffset.width : 0),
                                    y: e.y + (lifted ? dragOffset.height : 0))
                            .zIndex(lifted ? 1 : 0)
                            .onTapGesture { onOpen(e.id) }
                            .onLongPressGesture(minimumDuration: 0.6) { onMenu(e.id) }
                            .gesture(stackDrag(e))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(zoom * zoomDelta)
                .offset(x: pan.width + panDelta.width, y: pan.height + panDelta.height)
                .allowsHitTesting(true)

                if store.liveEntries.isEmpty {
                    Text("Tap the pencil to start your first entry")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($panDelta) { v, state, _ in state = v.translation }
            .onEnded { v in pan.width += v.translation.width; pan.height += v.translation.height }
    }

    private func magnifyGesture() -> some Gesture {
        MagnificationGesture()
            .updating($zoomDelta) { v, state, _ in state = v }
            .onEnded { v in zoom = min(2.5, max(0.3, zoom * v)) }
    }

    private func stackDrag(_ e: Entry) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                draggingID = e.id
                dragOffset = CGSize(width: v.translation.width / zoom, height: v.translation.height / zoom)
            }
            .onEnded { v in
                let p = Pt(e.x + v.translation.width / zoom, e.y + v.translation.height / zoom)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.drop(e.id, at: p, snap: settings.snapToGrid)
                    draggingID = nil
                    dragOffset = .zero
                }
            }
    }
}

/// One stack on the wall: up to the top three pages, slightly fanned, with its fasteners.
struct StackThumb: View {
    @Environment(\.wallRenderer) private var renderer
    let entry: Entry
    let pages: [Page]
    let lifted: Bool

    var body: some View {
        let shown = Array(pages.suffix(3))
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, p in
                PageCardView(page: p, lift: lifted ? 1 : (i == shown.count - 1 ? 0.2 : 0))
                    .offset(x: CGFloat(i - (shown.count - 1)) * 2.5, y: CGFloat(i - (shown.count - 1)) * 2.5)
            }
            ForEach(Array(entry.fasteners.enumerated()), id: \.offset) { _, f in
                renderer.fastener(FastenerRenderSpec(kind: f.kind,
                                                     look: FastenerLook.make(kind: f.kind, seed: f.seedValue),
                                                     pageSize: PageCardView.nominal))
            }
            if pages.count > 3 {
                Text("\(pages.count)")
                    .font(.caption2.weight(.bold)).foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .offset(x: 100, y: 140)
            }
        }
        .frame(width: PageCardView.nominal.width, height: PageCardView.nominal.height)
        .rotationEffect(.degrees(entry.rot))
        .scaleEffect(lifted ? 1.05 : 1)
    }
}
