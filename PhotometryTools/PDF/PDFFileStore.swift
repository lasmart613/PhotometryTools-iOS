import Foundation

/// Temp-file cache for manuals and generated service-report PDFs.
/// PDFKit loads these local files; nothing here is committed to the bundle.
enum PDFFileStore {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tsp-pdfs", isDirectory: true)
    }

    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func safeFilename(_ name: String, ext: String = "pdf") -> String {
        let base = name
            .replacingOccurrences(of: "[\\\\/:*?\"<>|\\n\\r]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = base.isEmpty ? "Document" : String(base.prefix(80))
        let suffix = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
        if trimmed.lowercased().hasSuffix(".\(suffix.lowercased())") {
            return trimmed
        }
        return "\(trimmed).\(suffix)"
    }

    static func write(_ data: Data, suggestedName: String) throws -> URL {
        try prepareDirectory()
        let url = directory.appendingPathComponent(safeFilename(suggestedName))
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    static func download(from remote: URL, suggestedName: String) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: remote)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            throw ManualURLClient.Failure.http(status, "Download failed (\(status)).")
        }
        let data = try Data(contentsOf: temp)
        try? FileManager.default.removeItem(at: temp)
        guard isPDF(data) else {
            throw ManualURLClient.Failure.invalidResponse
        }
        return try write(data, suggestedName: suggestedName)
    }

    static func writeBase64(_ base64: String, suggestedName: String) throws -> URL {
        let cleaned = base64
            .replacingOccurrences(of: "data:application/pdf;base64,", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        guard let data = Data(base64Encoded: cleaned), isPDF(data) else {
            throw ManualURLClient.Failure.invalidResponse
        }
        return try write(data, suggestedName: suggestedName)
    }

    static func resolvedLocalFile(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let url: URL
        if trimmed.hasPrefix("file://"), let parsed = URL(string: trimmed) {
            url = parsed
        } else if trimmed.hasPrefix("/") {
            url = URL(fileURLWithPath: trimmed)
        } else {
            return nil
        }

        let path = url.standardizedFileURL.path
        let allowed = [
            directory.standardizedFileURL.path,
            FileManager.default.temporaryDirectory.standardizedFileURL.path,
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.standardizedFileURL.path
        ].compactMap { $0 }
        guard allowed.contains(where: { path.hasPrefix($0) }) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return url
    }

    static func isPDF(_ data: Data) -> Bool {
        data.starts(with: [0x25, 0x50, 0x44, 0x46]) // %PDF
    }
}
