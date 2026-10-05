import Foundation

/// Injected into the live site and the bundled customer pages.
enum CardScanPageScript {
    static var source: String {
        guard let url = Bundle.main.url(forResource: "CardScanPageScript", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else {
            return ""
        }
        return text
    }
}
