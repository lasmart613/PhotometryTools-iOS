import Foundation

/// Encodes a Supabase session the way Android HTML expects:
/// raw session JSON, optional `{ currentSession, expiresAt }` wrap,
/// and `?_s=` = base64(JSON of access + refresh tokens).
enum TSPSessionJSON {
    struct Tokens {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Double?
    }

    static func tokens(from json: String) -> Tokens? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let session: [String: Any]
        if let wrapped = root["currentSession"] as? [String: Any] {
            session = wrapped
        } else {
            session = root
        }

        guard let access = session["access_token"] as? String, !access.isEmpty else {
            return nil
        }
        let refresh = session["refresh_token"] as? String ?? ""
        let expires = number(session["expires_at"]) ?? number(root["expiresAt"])
        return Tokens(accessToken: access, refreshToken: refresh, expiresAt: expires)
    }

    /// localStorage `tsp-auth-token` value (wrapped format used by restoreSession).
    static func localStorageValue(from json: String) -> String {
        guard let tokens = tokens(from: json),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return json
        }

        let session: [String: Any]
        if let wrapped = root["currentSession"] as? [String: Any] {
            session = wrapped
        } else {
            session = root
        }

        let payload: [String: Any] = [
            "currentSession": session,
            "expiresAt": tokens.expiresAt as Any
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: encoded, encoding: .utf8) else {
            return json
        }
        return string
    }

    /// Android `getSessionUrlParam()` — `_s=<base64({access_token,refresh_token,expires_at})>`.
    static func navigationQueryItem(from json: String) -> String? {
        guard let tokens = tokens(from: json) else { return nil }

        var minimal: [String: Any] = [
            "access_token": tokens.accessToken
        ]
        if !tokens.refreshToken.isEmpty {
            minimal["refresh_token"] = tokens.refreshToken
        }
        if let expires = tokens.expiresAt {
            minimal["expires_at"] = expires
        }

        guard let data = try? JSONSerialization.data(withJSONObject: minimal) else {
            return nil
        }
        return "_s=" + data.base64EncodedString()
    }

    static func encode(accessToken: String, refreshToken: String, expiresAt: Double?) -> String? {
        var payload: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "token_type": "bearer"
        ]
        if let expiresAt {
            payload["expires_at"] = expiresAt
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
