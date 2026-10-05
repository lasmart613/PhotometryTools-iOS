import Foundation

/// JSON bodies for the same `organizations` / `organization_customers` / `contacts`
/// writes the live Customers pages perform. Empty optionals are omitted.
enum CustomerCardPayload {
    static func ticketPrefix(for company: String) -> String {
        let alphanumeric = company.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let prefix = String(String.UnicodeScalarView(alphanumeric).prefix(3)).uppercased()
        return prefix.isEmpty ? "CUS" : prefix
    }

    static func organizationInsert(fields: BusinessCardFields, userID: String) -> [String: Any] {
        var body = organizationFields(fields)
        body["name"] = fields.company.trimmedCardField
        body["type"] = "customer"
        body["is_active"] = true
        body["ticket_prefix"] = ticketPrefix(for: fields.company)
        if !userID.isEmpty {
            body["created_by"] = userID
        }
        return body
    }

    static func organizationUpdate(fields: BusinessCardFields) -> [String: Any] {
        var body = organizationFields(fields)
        let company = fields.company.trimmedCardField
        if !company.isEmpty {
            body["name"] = company
        }
        body["updated_at"] = ISO8601DateFormatter().string(from: Date())
        return body
    }

    static func linkInsert(
        serviceOrganizationID: String,
        customerOrganizationID: String,
        userID: String
    ) -> [String: Any] {
        var body: [String: Any] = [
            "service_organization_id": serviceOrganizationID,
            "customer_organization_id": customerOrganizationID
        ]
        if !userID.isEmpty {
            body["created_by"] = userID
        }
        return body
    }

    static func contactInsert(organizationID: String, fields: BusinessCardFields) -> [String: Any]? {
        var body = contactFields(fields)
        guard !body.isEmpty else { return nil }
        body["organization_id"] = organizationID
        body["is_primary"] = true
        return body
    }

    static func contactUpdate(fields: BusinessCardFields) -> [String: Any] {
        var body = contactFields(fields)
        if !body.isEmpty {
            body["updated_at"] = ISO8601DateFormatter().string(from: Date())
        }
        return body
    }

    /// PostgREST schema-cache errors name a column we can drop and retry.
    /// Null-value errors are not column drops.
    static func missingColumn(in message: String) -> String? {
        let patterns = [
            #"Could not find the '([^']+)' column"#,
            #"column \"([^\"]+)\" of relation"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(message.startIndex..<message.endIndex, in: message)
            guard let match = regex.firstMatch(in: message, options: [], range: range),
                  match.numberOfRanges > 1,
                  let columnRange = Range(match.range(at: 1), in: message) else { continue }
            let column = String(message[columnRange])
            if !column.isEmpty { return column }
        }
        return nil
    }

    private static func organizationFields(_ fields: BusinessCardFields) -> [String: Any] {
        let fields = fields.trimmed
        var body: [String: Any] = [:]
        put(fields.phone, key: "phone", into: &body)
        put(fields.email, key: "email", into: &body)
        put(fields.address, key: "address", into: &body)
        put(fields.city, key: "city", into: &body)
        put(fields.state.uppercased(), key: "state", into: &body)
        put(fields.zip, key: "zip", into: &body)
        put(fields.website, key: "website", into: &body)
        put(fields.name, key: "contact_name", into: &body)
        return body
    }

    private static func contactFields(_ fields: BusinessCardFields) -> [String: Any] {
        let fields = fields.trimmed
        var body: [String: Any] = [:]
        let parts = splitPersonName(fields.name)
        put(parts.first, key: "first_name", into: &body)
        put(parts.last, key: "last_name", into: &body)
        put(fields.title, key: "title", into: &body)
        put(fields.phone, key: "phone", into: &body)
        put(fields.email, key: "email", into: &body)
        return body
    }

    static func splitPersonName(_ name: String) -> (first: String, last: String) {
        var words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        let honorifics: Set<String> = ["dr", "dr.", "mr", "mr.", "mrs", "mrs.", "ms", "ms.", "prof", "prof."]
        while let first = words.first, honorifics.contains(first.lowercased()) {
            words.removeFirst()
        }
        guard let first = words.first else { return ("", "") }
        return (first, words.dropFirst().joined(separator: " "))
    }

    private static func put(_ value: String, key: String, into body: inout [String: Any]) {
        let trimmed = value.trimmedCardField
        if !trimmed.isEmpty {
            body[key] = trimmed
        }
    }
}
