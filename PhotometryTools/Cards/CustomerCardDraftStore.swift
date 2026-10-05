import Foundation

enum CardCustomerMode: String, Codable, Equatable, Sendable {
    case create
    case update
}

/// A confirmed card the device still needs to write to Supabase.
/// The photo is never stored — only the fields the user saved.
struct CustomerCardDraft: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var mode: CardCustomerMode
    var organizationID: String?
    var needsLink: Bool
    var contactSynced: Bool = false
    var fields: BusinessCardFields
    var createdAt: Date
    var lastError: String?
    var pauseAutoRetry: Bool
}

final class CustomerCardDraftStore: @unchecked Sendable {
    static let shared = CustomerCardDraftStore()

    private let fileURL: URL
    private let lock = NSLock()

    init(directory: URL? = nil) {
        let folder = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("customer-card-drafts.json")
    }

    func all() -> [CustomerCardDraft] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked().sorted { $0.createdAt < $1.createdAt }
    }

    func upsert(_ draft: CustomerCardDraft) {
        lock.lock()
        defer { lock.unlock() }
        var drafts = loadUnlocked().filter { $0.id != draft.id }
        drafts.append(draft)
        writeUnlocked(drafts)
    }

    func remove(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        writeUnlocked(loadUnlocked().filter { $0.id != id })
    }

    private func loadUnlocked() -> [CustomerCardDraft] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CustomerCardDraft].self, from: data)) ?? []
    }

    private func writeUnlocked(_ drafts: [CustomerCardDraft]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(drafts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PhotometryTools", isDirectory: true)
    }
}
