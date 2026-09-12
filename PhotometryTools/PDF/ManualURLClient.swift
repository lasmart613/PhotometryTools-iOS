import Foundation

/// Calls the deployed `get-manual-url` Edge Function on project `yljztfajyvjzqikxdddf`.
/// Same contract as Android `pdf_viewer.html`: POST `{ storage_path }` with the
/// signed-in JWT. Ownership is enforced server-side (`user_manuals`).
enum ManualURLClient {
    struct CatalogRow: Sendable {
        var id: Int?
        var title: String
        var isFolder: Bool
        var storagePath: String
        var entryFilePath: String?
        var chapters: [Chapter]
    }

    struct Chapter: Sendable {
        var title: String
        var storagePath: String
        var order: Int
    }

    enum Failure: LocalizedError {
        case notSignedIn
        case missingPath
        case notConfigured
        case http(Int, String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in to open manuals."
            case .missingPath:
                return "No manual file was specified."
            case .notConfigured:
                return "Supabase is not configured."
            case .http(let status, let message):
                if status == 401 { return "Session expired. Sign in again." }
                if status == 403 { return message.isEmpty ? "You do not have access to this manual." : message }
                return message.isEmpty ? "Manual request failed (\(status))." : message
            case .invalidResponse:
                return "The manual service returned an unexpected response."
            }
        }
    }

    static func signedURL(
        storagePath: String,
        accessToken: String,
        anonKey: String
    ) async throws -> URL {
        let path = storagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw Failure.missingPath }
        guard !accessToken.isEmpty else { throw Failure.notSignedIn }
        guard !anonKey.isEmpty else { throw Failure.notConfigured }

        var request = URLRequest(url: AppConfig.supabaseURL.appending(path: "functions/v1/get-manual-url"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["storage_path": path])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let errorText = stringValue(body["error"]) ?? stringValue(body["details"]) ?? ""

        guard (200..<300).contains(status) else {
            throw Failure.http(status, errorText)
        }
        guard let raw = stringValue(body["url"]), let url = URL(string: raw) else {
            throw Failure.invalidResponse
        }
        return url
    }

    /// Same PostgREST read `pdf_viewer.html` uses for folder manuals + chapter grids.
    static func catalogRow(
        manualID: Int,
        accessToken: String,
        anonKey: String
    ) async throws -> CatalogRow? {
        guard !accessToken.isEmpty else { throw Failure.notSignedIn }

        var components = URLComponents(
            url: AppConfig.supabaseURL.appending(path: "rest/v1/manuals"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(manualID)"),
            URLQueryItem(name: "select", value: "id,title,is_folder,entry_file_path,chapter_metadata,storage_path"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { throw Failure.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else {
            return nil
        }
        return parseCatalogRow(row)
    }

    static func parseCatalogRow(_ row: [String: Any]) -> CatalogRow {
        let storage = stringValue(row["storage_path"]) ?? ""
        return CatalogRow(
            id: intValue(row["id"]),
            title: stringValue(row["title"]) ?? "Service Manual",
            isFolder: boolValue(row["is_folder"]),
            storagePath: storage,
            entryFilePath: stringValue(row["entry_file_path"]),
            chapters: parseChapters(row["chapter_metadata"], folderPrefix: storage)
        )
    }

    static func resolvedStoragePath(folderPrefix: String, entryFilePath: String) -> String {
        let entry = entryFilePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if entry.isEmpty { return folderPrefix }
        if entry.lowercased().hasPrefix("http") { return entry }
        if entry.hasPrefix("shared/") { return entry }
        let base = folderPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.isEmpty { return entry }
        if entry == base || entry.hasPrefix(base + "/") { return entry }
        return "\(base)/\(entry)"
    }

    static func looksLikePDFFile(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".pdf")
    }

    private static func parseChapters(_ raw: Any?, folderPrefix: String) -> [Chapter] {
        let array: [[String: Any]]
        if let list = raw as? [[String: Any]] {
            array = list
        } else if let text = raw as? String,
                  let data = text.data(using: .utf8),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            array = list
        } else {
            return []
        }

        return array.compactMap { item in
            let path = stringValue(item["storage_path"]) ?? stringValue(item["path"]) ?? ""
            guard !path.isEmpty else { return nil }
            let resolved = path.contains("/") ? path : resolvedStoragePath(folderPrefix: folderPrefix, entryFilePath: path)
            return Chapter(
                title: stringValue(item["title"]) ?? (resolved as NSString).lastPathComponent,
                storagePath: resolved,
                order: intValue(item["order"]) ?? 99
            )
        }
        .sorted { $0.order < $1.order }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let n as NSNumber:
            return n.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let n as Int: return n
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["1", "true", "t", "yes"].contains(s.lowercased())
        default: return false
        }
    }
}
