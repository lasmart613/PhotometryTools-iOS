import Foundation

/// Which customer screen the live site or bundled HTML is showing.
enum CardCustomerPage: Equatable, Sendable {
    case none
    case directory
    case profile(String)

    var profileID: String? {
        if case .profile(let id) = self { return id }
        return nil
    }

    var scanTitle: String? {
        switch self {
        case .none: return nil
        case .directory: return "Scan card"
        case .profile: return "Update from card"
        }
    }

    static func resolve(_ url: URL?) -> CardCustomerPage {
        guard let url else { return .none }
        let fileName = url.lastPathComponent.lowercased()
        if fileName == "customer_directory.html" {
            return .directory
        }
        if fileName == "customer_profile.html" {
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "id" })?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return id.isEmpty ? .none : .profile(id)
        }

        let host = url.host?.lowercased() ?? ""
        let isLive = host == "repairplanet.net" || host.hasSuffix(".repairplanet.net")
        let isFile = url.isFileURL
        guard isLive || isFile else { return .none }

        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first?.lowercased(), first == "customers" else { return .none }
        if parts.count == 1 {
            return .directory
        }
        if parts.count == 2 {
            let id = parts[1].removingPercentEncoding ?? parts[1]
            let blocked: Set<String> = ["new", "layout", "page"]
            if blocked.contains(id.lowercased()) || id.isEmpty {
                return .none
            }
            return .profile(id)
        }
        return .none
    }
}
