import SwiftUI
import JournalCore

struct JournalRootView: View {
    @EnvironmentObject var store: JournalStore
    @EnvironmentObject var settings: JournalSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private struct EntryRef: Identifiable { let id: String; var page = 0 }

    @State private var editing: EntryRef?
    @State private var fanning: EntryRef?
    @State private var menuFor: EntryRef?
    @State private var showSettings = false
    @State private var status = ""
    @State private var zoom: CGFloat = 0.6

    var body: some View {
        NavigationStack {
            WallView(zoom: $zoom,
                     onOpen: { fanning = EntryRef(id: $0) },
                     onMenu: { menuFor = EntryRef(id: $0) })
                .navigationTitle("Journal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button { Task { await sync() } } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        Button { settings.snapToGrid.toggle() } label: {
                            Image(systemName: settings.snapToGrid ? "square.grid.3x3.fill" : "square.grid.3x3")
                        }
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        Button {
                            editing = EntryRef(id: store.newEntry())
                        } label: { Image(systemName: "square.and.pencil") }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !status.isEmpty {
                        Text(status).font(.footnote).padding(8)
                            .background(Capsule().fill(.ultraThinMaterial)).padding(.bottom, 6)
                    }
                }
        }
        .fullScreenCover(item: $editing) { ref in
            EntryEditorView(entryID: ref.id, pageIndex: ref.page, onDone: finishedEditing)
        }
        .fullScreenCover(item: $fanning) { ref in
            StackFanView(entryID: ref.id) { page in
                fanning = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editing = EntryRef(id: ref.id, page: page) }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { JournalSettingsView(onSync: { Task { await sync() } }) }
        }
        .confirmationDialog("Stack", isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }),
                            presenting: menuFor) { ref in
            Button("Add a pin") { store.addFastener(.pin, to: ref.id) }
            Button("Add a staple") { store.addFastener(.staple, to: ref.id) }
            Button("Add tape") { store.addFastener(.tape, to: ref.id) }
            Button("Remove last fastener") {
                if let e = store.data.entries[ref.id], !e.fasteners.isEmpty {
                    store.removeFastener(at: e.fasteners.count - 1, from: ref.id)
                }
            }
            Button("Delete entry", role: .destructive) { store.deleteEntry(ref.id) }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: settings.snapToGrid) { on in withAnimation(.spring()) { store.setSnap(on) } }
        .onChange(of: scenePhase) { phase in if phase == .active { Task { await sync() } } }
        .task { await sync() }
    }

    /// After Done: the wall appears close up and pulls back, as if the page were being pinned up.
    private func finishedEditing() {
        zoom = 1.4
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.8)) { zoom = 0.6 }
        }
        Task { await sync() }
    }

    private func sync() async {
        status = await JournalSyncClient.sync(store: store, settings: settings)
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        status = ""
    }
}
