import Foundation
import UIKit

/// Native side of `Android.getManualUrl` / `openPdf` / `sharePdf` / `printReport`
/// and the `pdf_viewer.html` intercept used by `manual_library.html`.
@MainActor
final class TSPPDFBridge {
    static let shared = TSPPDFBridge()

    private let reportRenderer = ReportPDFRenderer()

    private init() {}

    func credentials() async throws -> (token: String, anon: String) {
        guard let anon = AuthService.shared.anonKey, !anon.isEmpty else {
            throw ManualURLClient.Failure.notConfigured
        }
        guard let token = await AuthService.shared.validAccessToken(), !token.isEmpty else {
            throw ManualURLClient.Failure.notSignedIn
        }
        return (token, anon)
    }

    func signedManualURL(storagePath: String) async throws -> URL {
        let creds = try await credentials()
        return try await ManualURLClient.signedURL(
            storagePath: storagePath,
            accessToken: creds.token,
            anonKey: creds.anon
        )
    }

    func openManual(storagePath: String, title: String, manualID: Int?) async {
        do {
            if let manualID {
                let creds = try await credentials()
                if let row = try await ManualURLClient.catalogRow(
                    manualID: manualID,
                    accessToken: creds.token,
                    anonKey: creds.anon
                ) {
                    if !row.chapters.isEmpty {
                        PDFHost.presentChapters(row.chapters, title: row.title.isEmpty ? title : row.title) { [weak self] chapter in
                            Task { @MainActor in
                                await self?.openSignedPDF(storagePath: chapter.storagePath, title: chapter.title)
                            }
                        }
                        return
                    }
                    if let entry = row.entryFilePath, !entry.isEmpty {
                        let path = ManualURLClient.resolvedStoragePath(
                            folderPrefix: row.storagePath.isEmpty ? storagePath : row.storagePath,
                            entryFilePath: entry
                        )
                        await openSignedPDF(storagePath: path, title: row.title.isEmpty ? title : row.title)
                        return
                    }
                    if !storagePath.isEmpty {
                        await openSignedPDF(storagePath: storagePath, title: title.isEmpty ? row.title : title)
                        return
                    }
                    if ManualURLClient.looksLikePDFFile(row.storagePath) {
                        await openSignedPDF(storagePath: row.storagePath, title: title.isEmpty ? row.title : title)
                        return
                    }
                    throw ManualURLClient.Failure.http(
                        400,
                        "This manual is a folder without a chapter list or entry file."
                    )
                }
            }

            var path = storagePath
            if path.isEmpty {
                throw ManualURLClient.Failure.missingPath
            }
            if !ManualURLClient.looksLikePDFFile(path) && !path.lowercased().hasPrefix("http") {
                throw ManualURLClient.Failure.http(
                    400,
                    "This manual needs a PDF file path. Open it again from the library after adding it to My Library."
                )
            }
            await openSignedPDF(storagePath: path, title: title)
        } catch {
            PDFHost.presentAlert(title: "Manual unavailable", message: error.localizedDescription)
        }
    }

    func openSignedPDF(storagePath: String, title: String) async {
        do {
            let remote = try await signedManualURL(storagePath: storagePath)
            let file = try await PDFFileStore.download(
                from: remote,
                suggestedName: title.isEmpty ? (storagePath as NSString).lastPathComponent : title
            )
            PDFHost.presentViewer(fileURL: file, title: title.isEmpty ? "Service Manual" : title)
        } catch {
            PDFHost.presentAlert(title: "Could not open PDF", message: error.localizedDescription)
        }
    }

    func openOrShare(spec: [String: Any], share: Bool) async throws -> String {
        let title = stringValue(spec["title"]) ?? stringValue(spec["jobName"]) ?? "Document"
        let fileURL = try await materializeFile(from: spec, title: title)
        if share {
            PDFHost.presentShareSheet(fileURL: fileURL, title: title)
        } else {
            PDFHost.presentViewer(fileURL: fileURL, title: title)
        }
        return fileURL.path
    }

    func printReport(html: String, jobName: String) async {
        let name = jobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Service Report"
            : jobName
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            PDFHost.presentAlert(title: "PDF export failed", message: "The report HTML was empty.")
            return
        }
        do {
            let data = try await reportRenderer.render(html: html)
            let file = try PDFFileStore.write(data, suggestedName: name)
            PDFHost.presentViewer(fileURL: file, title: name)
        } catch {
            PDFHost.presentAlert(title: "PDF export failed", message: error.localizedDescription)
        }
    }

    func handlePDFViewerNavigation(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ name: String) -> String {
            items.first(where: { $0.name == name })?.value ?? ""
        }
        let storagePath = query("storage_path")
        let title = query("title").removingPercentEncoding ?? query("title")
        let manualID = Int(query("manual_id"))
        Task { await openManual(storagePath: storagePath, title: title, manualID: manualID) }
    }

    private func materializeFile(from spec: [String: Any], title: String) async throws -> URL {
        if let base64 = stringValue(spec["base64"]) ?? stringValue(spec["data"]) {
            return try PDFFileStore.writeBase64(base64, suggestedName: title)
        }

        let raw = stringValue(spec["url"])
            ?? stringValue(spec["path"])
            ?? stringValue(spec["file"])
            ?? stringValue(spec["storage_path"])
            ?? ""

        if raw.isEmpty {
            throw ManualURLClient.Failure.missingPath
        }

        if raw.lowercased().hasPrefix("data:application/pdf") {
            return try PDFFileStore.writeBase64(raw, suggestedName: title)
        }

        if let local = PDFFileStore.resolvedLocalFile(from: raw) {
            return local
        }

        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            guard let remote = URL(string: raw) else { throw ManualURLClient.Failure.invalidResponse }
            return try await PDFFileStore.download(from: remote, suggestedName: title)
        }

        if raw.lowercased().hasPrefix("blob:") {
            throw ManualURLClient.Failure.http(
                400,
                "Blob URLs must be sent as base64 (the iOS Android.openPdf shim does this)."
            )
        }

        let remote = try await signedManualURL(storagePath: raw)
        return try await PDFFileStore.download(from: remote, suggestedName: title)
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }
}
