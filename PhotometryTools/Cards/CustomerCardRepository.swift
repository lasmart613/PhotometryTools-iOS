import Foundation

enum CardCommitResult {
    case finished(CustomerCardDraft)
    case failed(CustomerCardDraft, CardSaveFailure)
}

struct CardSaveFailure: Error, LocalizedError {
    enum Kind: Sendable {
        case retryable
        case rejected
    }

    var kind: Kind
    var message: String

    var shouldQueue: Bool { kind == .retryable }

    var errorDescription: String? { message }

    static func retryable(_ message: String) -> CardSaveFailure {
        CardSaveFailure(kind: .retryable, message: message)
    }

    static func rejected(_ message: String) -> CardSaveFailure {
        CardSaveFailure(kind: .rejected, message: message)
    }
}

/// Writes a confirmed card with the signed-in Supabase session.
/// Recognition never comes here — only fields the user tapped Save on.
@MainActor
enum CustomerCardRepository {
    static func fetchFields(organizationID: String) async -> BusinessCardFields? {
        guard let creds = credentials() else { return nil }
        do {
            let orgRows = try await select(
                table: "organizations",
                query: [
                    URLQueryItem(name: "id", value: "eq.\(organizationID)"),
                    URLQueryItem(name: "select", value: "name,address,city,state,zip,phone,email,contact_name,website"),
                    URLQueryItem(name: "limit", value: "1")
                ],
                token: creds.token,
                anon: creds.anon
            )
            guard let org = orgRows.first else { return nil }
            let contacts = try await select(
                table: "contacts",
                query: [
                    URLQueryItem(name: "organization_id", value: "eq.\(organizationID)"),
                    URLQueryItem(name: "is_primary", value: "eq.true"),
                    URLQueryItem(name: "select", value: "first_name,last_name,title,phone,email"),
                    URLQueryItem(name: "limit", value: "1")
                ],
                token: creds.token,
                anon: creds.anon
            )
            return fields(from: org, contact: contacts.first)
        } catch {
            return nil
        }
    }

    /// Returns the latest draft when a later step fails after the organization row exists,
    /// so a retry does not insert a second customer. `inout` is not used: a thrown error
    /// would drop those writes.
    static func commit(_ draft: CustomerCardDraft) async -> CardCommitResult {
        var draft = draft
        _ = await AuthService.shared.validAccessToken()
        guard let creds = credentials() else {
            return .failed(draft, .rejected("Sign in again before saving this customer."))
        }
        let fields = draft.fields.trimmed
        draft.fields = fields
        guard fields.hasAnyValue else {
            return .failed(draft, .rejected("Enter at least one field from the card."))
        }

        do {
            switch draft.mode {
            case .create:
                guard !fields.company.isEmpty else {
                    return .failed(draft, .rejected("Company is required. It becomes the customer name."))
                }
                let serviceID = try await serviceOrganizationID(credentials: creds)
                if draft.organizationID == nil {
                    let created = try await write(
                        method: "POST",
                        table: "organizations",
                        query: [],
                        body: CustomerCardPayload.organizationInsert(fields: fields, userID: creds.userID),
                        prefer: "return=representation",
                        credentials: creds
                    )
                    guard let id = stringValue(created["id"]), !id.isEmpty else {
                        return .failed(draft, .rejected("The customer was not created."))
                    }
                    draft.organizationID = id
                    draft.needsLink = true
                } else if let customerID = draft.organizationID {
                    _ = try await write(
                        method: "PATCH",
                        table: "organizations",
                        query: [URLQueryItem(name: "id", value: "eq.\(customerID)")],
                        body: CustomerCardPayload.organizationUpdate(fields: fields),
                        prefer: "return=minimal",
                        credentials: creds
                    )
                }
                if draft.needsLink, let customerID = draft.organizationID {
                    do {
                        _ = try await write(
                            method: "POST",
                            table: "organization_customers",
                            query: [],
                            body: CustomerCardPayload.linkInsert(
                                serviceOrganizationID: serviceID,
                                customerOrganizationID: customerID,
                                userID: creds.userID
                            ),
                            prefer: "return=minimal",
                            credentials: creds
                        )
                        draft.needsLink = false
                    } catch let error as CardSaveFailure where isDuplicate(error.message) {
                        draft.needsLink = false
                    }
                }
                if let customerID = draft.organizationID, !draft.contactSynced {
                    await syncContact(organizationID: customerID, fields: fields, credentials: creds)
                    draft.contactSynced = true
                }
            case .update:
                guard let customerID = draft.organizationID, !customerID.isEmpty else {
                    return .failed(draft, .rejected("Open a customer profile, then use Update from card."))
                }
                _ = try await write(
                    method: "PATCH",
                    table: "organizations",
                    query: [URLQueryItem(name: "id", value: "eq.\(customerID)")],
                    body: CustomerCardPayload.organizationUpdate(fields: fields),
                    prefer: "return=minimal",
                    credentials: creds
                )
                if !draft.contactSynced {
                    await syncContact(organizationID: customerID, fields: fields, credentials: creds)
                    draft.contactSynced = true
                }
            }
            return .finished(draft)
        } catch let error as CardSaveFailure {
            return .failed(draft, error)
        } catch {
            return .failed(draft, .retryable(error.localizedDescription))
        }
    }

    // MARK: - Session

    private struct Credentials {
        var token: String
        var anon: String
        var userID: String
    }

    private static func credentials() -> Credentials? {
        guard let token = AuthService.shared.accessToken, !token.isEmpty,
              let anon = AppConfig.supabaseAnonKey, !anon.isEmpty,
              let userID = userID(from: token), !userID.isEmpty else {
            return nil
        }
        return Credentials(token: token, anon: anon, userID: userID)
    }

    static func userID(from accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String,
              !subject.isEmpty else {
            return nil
        }
        return subject
    }

    // MARK: - PostgREST

    private static func serviceOrganizationID(credentials: Credentials) async throws -> String {
        let rows = try await select(
            table: "user_profiles",
            query: [
                URLQueryItem(name: "id", value: "eq.\(credentials.userID)"),
                URLQueryItem(name: "select", value: "organization_id"),
                URLQueryItem(name: "limit", value: "1")
            ],
            token: credentials.token,
            anon: credentials.anon
        )
        guard let id = stringValue(rows.first?["organization_id"]), !id.isEmpty else {
            throw CardSaveFailure.rejected("Your service organization is not loaded yet. Open Customers while online, then save this card again.")
        }
        return id
    }

    private static func select(
        table: String,
        query: [URLQueryItem],
        token: String,
        anon: String
    ) async throws -> [[String: Any]] {
        let (data, status) = try await request(
            method: "GET",
            table: table,
            query: query,
            body: nil,
            prefer: nil,
            token: token,
            anon: anon
        )
        guard (200..<300).contains(status) else {
            throw failure(for: status, data: data)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private static func write(
        method: String,
        table: String,
        query: [URLQueryItem],
        body: [String: Any],
        prefer: String,
        credentials: Credentials
    ) async throws -> [String: Any] {
        var payload = body
        var last = "Save failed."
        for _ in 0..<8 {
            let (data, status) = try await request(
                method: method,
                table: table,
                query: query,
                body: payload,
                prefer: prefer,
                token: credentials.token,
                anon: credentials.anon
            )
            if (200..<300).contains(status) {
                if let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return row
                }
                if let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    return rows.first ?? [:]
                }
                return [:]
            }
            let message = serverMessage(data: data, status: status)
            last = message
            if let column = CustomerCardPayload.missingColumn(in: message), payload[column] != nil {
                payload.removeValue(forKey: column)
                continue
            }
            throw failure(for: status, data: data)
        }
        throw CardSaveFailure.rejected(last)
    }

    private static func syncContact(organizationID: String, fields: BusinessCardFields, credentials: Credentials) async {
        let update = CustomerCardPayload.contactUpdate(fields: fields)
        guard !update.isEmpty else { return }
        do {
            var existingID: String?
            let primary = try await select(
                table: "contacts",
                query: [
                    URLQueryItem(name: "organization_id", value: "eq.\(organizationID)"),
                    URLQueryItem(name: "is_primary", value: "eq.true"),
                    URLQueryItem(name: "select", value: "id"),
                    URLQueryItem(name: "limit", value: "1")
                ],
                token: credentials.token,
                anon: credentials.anon
            )
            existingID = stringValue(primary.first?["id"])
            if existingID == nil, !fields.email.trimmedCardField.isEmpty {
                let byEmail = try await select(
                    table: "contacts",
                    query: [
                        URLQueryItem(name: "organization_id", value: "eq.\(organizationID)"),
                        URLQueryItem(name: "email", value: "eq.\(fields.email.trimmedCardField)"),
                        URLQueryItem(name: "select", value: "id"),
                        URLQueryItem(name: "limit", value: "1")
                    ],
                    token: credentials.token,
                    anon: credentials.anon
                )
                existingID = stringValue(byEmail.first?["id"])
            }
            if let existingID {
                _ = try await write(
                    method: "PATCH",
                    table: "contacts",
                    query: [URLQueryItem(name: "id", value: "eq.\(existingID)")],
                    body: update,
                    prefer: "return=minimal",
                    credentials: credentials
                )
            } else if let insert = CustomerCardPayload.contactInsert(organizationID: organizationID, fields: fields) {
                _ = try await write(
                    method: "POST",
                    table: "contacts",
                    query: [],
                    body: insert,
                    prefer: "return=minimal",
                    credentials: credentials
                )
            }
        } catch {
            // The customer row is the source of truth. A contact-row miss can be edited on the profile.
        }
    }

    private static func request(
        method: String,
        table: String,
        query: [URLQueryItem],
        body: [String: Any]?,
        prefer: String?,
        token: String,
        anon: String
    ) async throws -> (Data, Int) {
        var components = URLComponents(
            url: AppConfig.supabaseURL.appending(path: "rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw CardSaveFailure.rejected("Could not build the customer request.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anon, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            throw CardSaveFailure.retryable(offlineMessage(for: error))
        }
    }

    private static func failure(for status: Int, data: Data) -> CardSaveFailure {
        let message = serverMessage(data: data, status: status)
        if status == 408 || status == 429 || status >= 500 {
            return .retryable(message)
        }
        return .rejected(message)
    }

    private static func serverMessage(data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error", "details", "hint"] {
                if let value = json[key] as? String, !value.isEmpty { return value }
            }
        }
        let text = String(data: data, encoding: .utf8)?.trimmedCardField ?? ""
        return text.isEmpty ? "Save failed (\(status))." : text
    }

    private static func offlineMessage(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "You appear to be offline. This card stays on the device until it can sync."
        }
        return error.localizedDescription
    }

    private static func isDuplicate(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("23505") || lower.contains("duplicate") || lower.contains("unique")
    }

    private static func fields(from org: [String: Any], contact: [String: Any]?) -> BusinessCardFields {
        let contactName = [stringValue(contact?["first_name"]), stringValue(contact?["last_name"])]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return BusinessCardFields(
            name: contactName.isEmpty ? (stringValue(org["contact_name"]) ?? "") : contactName,
            title: stringValue(contact?["title"]) ?? "",
            company: stringValue(org["name"]) ?? "",
            phone: stringValue(contact?["phone"]) ?? stringValue(org["phone"]) ?? "",
            email: stringValue(contact?["email"]) ?? stringValue(org["email"]) ?? "",
            address: stringValue(org["address"]) ?? "",
            city: stringValue(org["city"]) ?? "",
            state: stringValue(org["state"]) ?? "",
            zip: stringValue(org["zip"]) ?? "",
            website: stringValue(org["website"]) ?? ""
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmedCardField
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
