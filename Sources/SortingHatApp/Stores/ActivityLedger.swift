import Foundation

struct ActivityLedger {
    let url: URL
    var retentionLimit: Int

    func load() -> [Activity] {
        guard let data = try? Data(contentsOf: url),
              let activities = try? JSONDecoder().decode([Activity].self, from: data) else { return [] }
        return Array(activities.prefix(retentionLimit))
    }

    func save(_ activities: [Activity]) throws {
        let data = try JSONEncoder().encode(Array(activities.prefix(retentionLimit)))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
