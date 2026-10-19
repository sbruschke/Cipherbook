import Foundation
import JournalCore

@MainActor
enum JournalSyncClient {
    static func sync(store: JournalStore, settings: JournalSettings) async -> String {
        guard let base = URL(string: settings.serverURL.trimmingCharacters(in: .whitespaces)), !settings.token.isEmpty
        else { return "Sync not configured" }
        func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
            var r = URLRequest(url: URL(string: path, relativeTo: base)!.absoluteURL)
            r.httpMethod = method; r.httpBody = body; r.timeoutInterval = 30
            r.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
            if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            return r
        }
        do {
            var pushed = 0
            while true {
                let batch = store.pending(limit: 200)
                if batch.isEmpty { break }
                let (data, resp) = try await URLSession.shared.data(
                    for: request("/sync/push", method: "POST", body: JSONEncoder().encode(PushBody(changes: batch))))
                if let h = resp as? HTTPURLResponse, h.statusCode == 401 { return "Check your token in Journal settings" }
                guard let h = resp as? HTTPURLResponse, h.statusCode == 200 else { return "Server error while pushing" }
                let results = try JSONDecoder().decode(PushReply.self, from: data).results
                store.settle(pushed: batch, results: results)
                pushed += batch.count
                if results.count < batch.count { break }
            }
            var pulled = 0
            while true {
                let (data, resp) = try await URLSession.shared.data(
                    for: request("/sync/pull?since=\(store.data.cursor)&limit=500"))
                guard let h = resp as? HTTPURLResponse, h.statusCode == 200 else { return "Server error while pulling" }
                let page = try JSONDecoder().decode(PullResponse.self, from: data)
                store.applyPull(page.changes, next: page.next)
                pulled += page.changes.count
                if !page.more { break }
            }
            return "Synced · sent \(pushed), received \(pulled)"
        } catch {
            return "Offline — will retry (\(error.localizedDescription))"
        }
    }

    private struct PushBody: Encodable { let changes: [SyncChange] }
    private struct PushReply: Decodable { let results: [PushResult] }
}
