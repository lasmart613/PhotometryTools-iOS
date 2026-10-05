import Foundation

/// Turns on-device text lines into customer fields. No network calls.
enum BusinessCardParser {
    static func parse(text: String) -> BusinessCardFields {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return parse(lines: lines)
    }

    static func parse(lines: [String]) -> BusinessCardFields {
        var pool = lines.flatMap(splitCompositeLine).map { $0.trimmedCardField }.filter { !$0.isEmpty }
        var fields = BusinessCardFields()

        var kept: [String] = []
        for line in pool {
            let email = firstMatch(in: line, pattern: emailPattern)
            let phone = firstPhone(in: line)
            let website = email == nil ? firstWebsite(in: line) : nil
            if fields.email.isEmpty, let email { fields.email = email }
            if fields.phone.isEmpty, let phone { fields.phone = phone }
            if fields.website.isEmpty, let website, website.lowercased() != email?.lowercased() {
                fields.website = website
            }
            let stripped = stripContacts(from: line)
            if !stripped.isEmpty {
                kept.append(stripped)
            }
        }
        pool = kept

        if let localityIndex = pool.firstIndex(where: { parseLocality($0) != nil }) {
            let locality = parseLocality(pool[localityIndex])!
            fields.city = locality.city
            fields.state = locality.state
            fields.zip = locality.zip
            var streetParts: [String] = []
            if let prefix = locality.street, !prefix.isEmpty {
                streetParts.append(prefix)
            }
            var consumed: Set<Int> = [localityIndex]
            var cursor = localityIndex - 1
            while cursor >= 0, isStreetOrSuite(pool[cursor]) {
                streetParts.insert(pool[cursor], at: 0)
                consumed.insert(cursor)
                cursor -= 1
            }
            cursor = localityIndex + 1
            while cursor < pool.count, isSuiteLine(pool[cursor]) {
                streetParts.append(pool[cursor])
                consumed.insert(cursor)
                cursor += 1
            }
            fields.address = streetParts.joined(separator: ", ")
            pool = pool.enumerated().compactMap { consumed.contains($0.offset) ? nil : $0.element }
        }

        var titles: [String] = []
        var companies: [String] = []
        var names: [String] = []
        var leftovers: [String] = []
        var streets: [String] = []

        var classified: [String] = []
        for line in pool {
            if let split = splitNameAndTitle(line) {
                classified.append(split.name)
                classified.append(split.title)
            } else {
                classified.append(line)
            }
        }

        for line in classified {
            if isStreetOrSuite(line) && !hasStrongCompany(line) && !isTitle(line) {
                streets.append(line)
            } else if isTitle(line) {
                titles.append(line)
            } else if hasStrongCompany(line) || hasWeakCompany(line) {
                companies.append(line)
            } else if isPersonName(line) {
                names.append(line)
            } else {
                leftovers.append(line)
            }
        }

        if fields.title.isEmpty { fields.title = titles.first ?? "" }
        if fields.company.isEmpty { fields.company = companies.first ?? "" }
        if fields.name.isEmpty { fields.name = names.first ?? "" }
        if fields.address.isEmpty {
            fields.address = streets.joined(separator: ", ")
        } else if !streets.isEmpty {
            fields.address = (streets + [fields.address]).joined(separator: ", ")
        }

        for line in leftovers {
            if fields.company.isEmpty, isShoutedCompany(line) {
                fields.company = line
                continue
            }
            if fields.name.isEmpty, isPersonName(line) || wordCount(line) >= 2 && wordCount(line) <= 4 && !line.contains(where: \.isNumber) {
                if !hasStrongCompany(line) && !isTitle(line) {
                    fields.name = line
                    continue
                }
            }
            if fields.company.isEmpty {
                fields.company = line
            }
        }

        if fields.state.count == 2 {
            fields.state = fields.state.uppercased()
        }
        return fields.trimmed
    }

    // MARK: - Line splitting

    private static func splitCompositeLine(_ line: String) -> [String] {
        line
            .replacingOccurrences(of: " • ", with: "\n")
            .replacingOccurrences(of: " · ", with: "\n")
            .replacingOccurrences(of: " | ", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    // MARK: - Contacts

    private static let emailPattern = #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#
    private static let phonePattern = #"(?:\+\d{1,3}[\s.\-]?)?(?:\(\d{3}\)|\d{3})[\s.\-]\d{3}[\s.\-]\d{4}"#

    private static func firstPhone(in line: String) -> String? {
        if let match = firstMatch(in: line, pattern: phonePattern) {
            return match.trimmedCardField
        }
        let digits = line.filter(\.isNumber)
        let compact = line.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) || $0 == "+" }
        if digits.count == 10, String(String.UnicodeScalarView(compact)).count <= 11, line.filter({ !$0.isNumber && $0 != "+" && $0 != " " && $0 != "-" && $0 != "." && $0 != "(" && $0 != ")" }).isEmpty {
            return line.trimmedCardField
        }
        return nil
    }

    private static func firstWebsite(in line: String) -> String? {
        let pattern = #"(?:https?:\/\/)?(?:www\.)?[A-Z0-9][A-Z0-9\-]*\.[A-Z]{2,}(?:\/[^\s]*)?"#
        guard let match = firstMatch(in: line, pattern: pattern) else { return nil }
        if match.contains("@") { return nil }
        let lower = match.lowercased()
        if lower.hasPrefix("http") || lower.hasPrefix("www.") || line.trimmedCardField.lowercased() == lower {
            return match
        }
        return nil
    }

    private static func stripContacts(from line: String) -> String {
        var text = line
        for pattern in [emailPattern, phonePattern, #"(?:https?:\/\/)?(?:www\.)?[A-Z0-9][A-Z0-9\-]*\.[A-Z]{2,}(?:\/[^\s]*)?"#] {
            text = replacingMatches(in: text, pattern: pattern, with: " ")
        }
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|•·,;:/-")))
        if trimmed.count < 2 { return "" }
        return trimmed
    }

    // MARK: - Address

    private struct Locality {
        var street: String?
        var city: String
        var state: String
        var zip: String
    }

    private static let stateAbbreviations: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
        "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT",
        "VA", "WA", "WV", "WI", "WY", "DC"
    ]

    private static let stateNames: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR", "california": "CA",
        "colorado": "CO", "connecticut": "CT", "delaware": "DE", "florida": "FL", "georgia": "GA",
        "hawaii": "HI", "idaho": "ID", "illinois": "IL", "indiana": "IN", "iowa": "IA",
        "kansas": "KS", "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
        "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
        "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV", "new hampshire": "NH",
        "new jersey": "NJ", "new mexico": "NM", "new york": "NY", "north carolina": "NC",
        "north dakota": "ND", "ohio": "OH", "oklahoma": "OK", "oregon": "OR", "pennsylvania": "PA",
        "rhode island": "RI", "south carolina": "SC", "south dakota": "SD", "tennessee": "TN",
        "texas": "TX", "utah": "UT", "vermont": "VT", "virginia": "VA", "washington": "WA",
        "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY", "district of columbia": "DC"
    ]

    private static func parseLocality(_ line: String) -> Locality? {
        let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if parts.count >= 2, let tail = parts.last, let stateZip = matchStateZip(tail) {
            let city = parts[parts.count - 2]
            if looksLikeCity(city), let state = normalizeState(stateZip.state) {
                let street = parts.dropLast(2).joined(separator: ", ")
                return Locality(street: street.isEmpty ? nil : street, city: city, state: state, zip: stateZip.zip)
            }
        }
        if let match = firstGroups(
            in: line,
            pattern: #"^(.+?)[\s,]+([A-Za-z]{2})\s+(\d{5}(?:-\d{4})?)\s*$"#
        ), match.count == 3, let state = normalizeState(match[1]), !match[0].contains(where: \.isNumber) {
            return Locality(street: nil, city: match[0].trimmingCharacters(in: .whitespaces), state: state, zip: match[2])
        }
        return nil
    }

    private static func matchStateZip(_ text: String) -> (state: String, zip: String)? {
        if let groups = firstGroups(in: text, pattern: #"^([A-Za-z]{2}|[A-Za-z][A-Za-z .]+)\s+(\d{5}(?:-\d{4})?)$"#),
           groups.count == 2 {
            return (groups[0], groups[1])
        }
        if let state = normalizeState(text) {
            // "MD" and "PA" are credentials as often as they are states. Without a ZIP,
            // keep "Dr. Maria Chen, MD" as a name.
            let key = text.trimmedCardField.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if suffixOnlyTokens.contains(key) { return nil }
            return (state, "")
        }
        return nil
    }

    private static func normalizeState(_ raw: String) -> String? {
        let trimmed = raw.trimmedCardField
        if trimmed.count == 2 {
            let upper = trimmed.uppercased()
            return stateAbbreviations.contains(upper) ? upper : nil
        }
        return stateNames[trimmed.lowercased()]
    }

    private static func looksLikeCity(_ value: String) -> Bool {
        let trimmed = value.trimmedCardField
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        if trimmed.contains(where: \.isNumber) { return false }
        if isSuiteLine(trimmed) { return false }
        return true
    }

    private static func isStreetOrSuite(_ line: String) -> Bool {
        if isSuiteLine(line) { return true }
        let lower = line.lowercased()
        if lower.contains("p.o. box") || lower.contains("po box") || lower.contains("p.o.box") { return true }
        let suffixes: Set<String> = [
            "street", "st", "avenue", "ave", "road", "rd", "boulevard", "blvd", "drive", "dr",
            "lane", "ln", "way", "court", "ct", "place", "pl", "parkway", "pkwy", "highway", "hwy",
            "circle", "cir", "terrace", "ter", "trail", "trl"
        ]
        let tokens = words(line)
        let streetTokens = tokens.filter { suffixes.contains($0) }
        if !streetTokens.isEmpty {
            // A leading "Dr." is an honorific. "123 Oak Dr" and "Oak Dr" stay streets.
            let onlyLeadingHonorific = streetTokens == ["dr"] && tokens.first == "dr" && !line.contains(where: \.isNumber)
            if !onlyLeadingHonorific { return true }
        }
        if let first = line.first, first.isNumber { return true }
        return false
    }

    private static func isSuiteLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("suite") || lower.hasPrefix("ste ") || lower.hasPrefix("ste.")
            || lower.hasPrefix("floor") || lower.hasPrefix("unit ") || lower.hasPrefix("apt ")
            || lower.hasPrefix("#")
    }

    // MARK: - Name / title / company

    private static let titleTokens: Set<String> = [
        "director", "manager", "engineer", "technician", "tech", "owner", "president", "ceo", "cfo",
        "coo", "cto", "founder", "specialist", "consultant", "coordinator", "representative", "bmet",
        "fse", "physician", "doctor", "md", "do", "rn", "np", "administrator", "admin", "sales",
        "vice", "vp", "chief", "partner", "principal", "supervisor", "operator", "dispatcher",
        "officer", "lead", "clinical", "biomed", "biomedical", "aesthetician"
    ]

    private static let strongCompanyTokens: Set<String> = [
        "inc", "llc", "ltd", "corp", "corporation", "company", "clinic", "clinics", "hospital",
        "center", "centre", "group", "associates", "pllc", "institute", "practice", "spa", "spas"
    ]

    private static let weakCompanyTokens: Set<String> = [
        "medical", "laser", "health", "healthcare", "dermatology", "surgery", "wellness",
        "aesthetic", "aesthetics", "systems", "services", "service", "solutions", "repair",
        "labs", "laboratory"
    ]

    private static let fillerTokens: Set<String> = [
        "field", "service", "services", "senior", "junior", "regional", "national", "technical",
        "laser", "medical", "clinical", "aesthetic", "biomedical", "customer", "account",
        "support", "operations", "operation", "general", "of", "and", "the", "for", "at"
    ]

    private static let honorificTokens: Set<String> = ["dr", "mr", "mrs", "ms", "prof"]

    private static let suffixOnlyTokens: Set<String> = ["md", "do", "phd", "rn", "np", "pa", "jr", "sr", "ii", "iii", "iv"]

    /// A job line such as "Clinical Director" or "Field Service Engineer".
    /// "Dr. Maria Chen, MD" stays a name: two non-title words remain.
    private static func isTitle(_ line: String) -> Bool {
        let tokens = words(line)
        guard !tokens.isEmpty, tokens.count <= 8 else { return false }
        guard tokens.contains(where: { titleTokens.contains($0) }) else { return false }
        if hasStrongCompany(line) { return false }
        let nameWords = tokens.filter {
            !titleTokens.contains($0) && !fillerTokens.contains($0) && !honorificTokens.contains($0)
        }
        return nameWords.count < 2
    }

    private static func splitNameAndTitle(_ line: String) -> (name: String, title: String)? {
        let parts = line.split(separator: ",", maxSplits: 1).map { String($0).trimmedCardField }.filter { !$0.isEmpty }
        guard parts.count == 2 else { return nil }
        let suffix = parts[1].lowercased().trimmingCharacters(in: .punctuationCharacters)
        if suffixOnlyTokens.contains(suffix) { return nil }
        guard isPersonName(parts[0]), isTitle(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    private static func hasStrongCompany(_ line: String) -> Bool {
        tokens(of: line).contains(where: { strongCompanyTokens.contains($0) })
    }

    private static func hasWeakCompany(_ line: String) -> Bool {
        tokens(of: line).contains(where: { weakCompanyTokens.contains($0) })
    }

    private static func isPersonName(_ line: String) -> Bool {
        if hasStrongCompany(line) { return false }
        var tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        let honorifics: Set<String> = ["dr", "dr.", "mr", "mr.", "mrs", "mrs.", "ms", "ms.", "prof", "prof."]
        let suffixes: Set<String> = ["md", "m.d.", "do", "d.o.", "phd", "ph.d.", "jr", "jr.", "sr", "sr.", "rn", "np", "pa", "ii", "iii", "iv"]
        while let first = tokens.first, honorifics.contains(first.lowercased()) {
            tokens.removeFirst()
        }
        while let last = tokens.last, suffixes.contains(last.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            tokens.removeLast()
        }
        guard tokens.count >= 2, tokens.count <= 5 else { return false }
        if tokens.contains(where: { $0.contains(where: \.isNumber) }) { return false }
        let particles: Set<String> = ["de", "del", "da", "di", "van", "von", "la", "le", "st", "st."]
        return tokens.allSatisfy { word in
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            if particles.contains(cleaned.lowercased()) { return true }
            if cleaned.count <= 2, cleaned.contains(".") { return true }
            guard let first = cleaned.first else { return false }
            return first.isUppercase
        }
    }

    private static func isShoutedCompany(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter)
        guard letters.count >= 6, wordCount(line) >= 2 else { return false }
        return letters.allSatisfy(\.isUppercase)
    }

    private static func words(_ line: String) -> [String] {
        line.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func tokens(of line: String) -> [String] {
        let compact = line.lowercased().replacingOccurrences(of: ".", with: "")
        return compact
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func wordCount(_ line: String) -> Int {
        line.split(whereSeparator: \.isWhitespace).count
    }

    // MARK: - Regex helpers

    private static func firstMatch(in text: String, pattern: String) -> String? {
        firstGroups(in: text, pattern: pattern)?.first
    }

    private static func firstGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var groups: [String] = []
        let start = match.numberOfRanges > 1 ? 1 : 0
        if match.numberOfRanges == 1 {
            guard let whole = Range(match.range, in: text) else { return nil }
            return [String(text[whole])]
        }
        for index in start..<match.numberOfRanges {
            guard let group = Range(match.range(at: index), in: text) else { return nil }
            groups.append(String(text[group]))
        }
        return groups
    }

    private static func replacingMatches(in text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}

#if CARD_PARSER_SELFTEST
@main
enum CardParserSelfTest {
    static func main() {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        let classic = BusinessCardParser.parse(text: """
        Jane Q. Smith
        Clinical Director
        Desert Dermatology, LLC
        123 Main St
        Phoenix, AZ 85001
        (602) 555-0199
        jane.smith@desertderm.com
        """)
        expect(classic.name == "Jane Q. Smith", "classic name \(classic.name)")
        expect(classic.title == "Clinical Director", "classic title \(classic.title)")
        expect(classic.company == "Desert Dermatology, LLC", "classic company \(classic.company)")
        expect(classic.phone == "(602) 555-0199", "classic phone \(classic.phone)")
        expect(classic.email == "jane.smith@desertderm.com", "classic email \(classic.email)")
        expect(classic.address == "123 Main St", "classic address \(classic.address)")
        expect(classic.city == "Phoenix", "classic city \(classic.city)")
        expect(classic.state == "AZ", "classic state \(classic.state)")
        expect(classic.zip == "85001", "classic zip \(classic.zip)")

        let inline = BusinessCardParser.parse(lines: [
            "ACME LASER SERVICE",
            "John Doe",
            "Field Service Engineer",
            "john@acme.com | 555.123.4567",
            "456 Oak Avenue, Suite 200, Austin, TX 78701"
        ])
        expect(inline.company == "ACME LASER SERVICE", "inline company \(inline.company)")
        expect(inline.name == "John Doe", "inline name \(inline.name)")
        expect(inline.title == "Field Service Engineer", "inline title \(inline.title)")
        expect(inline.email == "john@acme.com", "inline email \(inline.email)")
        expect(inline.phone == "555.123.4567", "inline phone \(inline.phone)")
        expect(inline.city == "Austin", "inline city \(inline.city)")
        expect(inline.state == "TX", "inline state \(inline.state)")
        expect(inline.zip == "78701", "inline zip \(inline.zip)")
        expect(inline.address.contains("456 Oak Avenue"), "inline street \(inline.address)")
        expect(inline.address.contains("Suite 200"), "inline suite \(inline.address)")

        let doctor = BusinessCardParser.parse(text: """
        Dr. Maria Chen, MD
        Owner
        Sunrise Medical Spa
        maria@sunrise.med
        +1 415-555-0100
        88 Market Street
        San Francisco CA 94105
        """)
        expect(doctor.name == "Dr. Maria Chen, MD", "doctor name \(doctor.name)")
        expect(doctor.title == "Owner", "doctor title \(doctor.title)")
        expect(doctor.company == "Sunrise Medical Spa", "doctor company \(doctor.company)")
        expect(doctor.city == "San Francisco", "doctor city \(doctor.city)")
        expect(doctor.state == "CA", "doctor state \(doctor.state)")
        expect(doctor.address == "88 Market Street", "doctor street \(doctor.address)")
        expect(doctor.phone.contains("415"), "doctor phone \(doctor.phone)")

        let director = BusinessCardParser.parse(lines: ["Medical Director", "Alex Kim"])
        expect(director.title == "Medical Director", "director title \(director.title)")
        expect(director.name == "Alex Kim", "director name \(director.name)")
        expect(director.company.isEmpty, "director company should be empty \(director.company)")

        expect(CustomerCardPayload.ticketPrefix(for: "Desert Dermatology, LLC") == "DES", "prefix DES")
        expect(CustomerCardPayload.ticketPrefix(for: "!!") == "CUS", "prefix CUS")
        expect(CustomerCardPayload.missingColumn(in: "Could not find the 'directory_contacts' column of 'organizations' in the schema cache") == "directory_contacts", "missing column")
        expect(CustomerCardPayload.missingColumn(in: "null value in column \"name\"") == nil, "null column is not stripped")

        let insert = CustomerCardPayload.organizationInsert(
            fields: BusinessCardFields(name: "Jane Q. Smith", company: "Desert Dermatology, LLC", phone: "602", email: ""),
            userID: "user-1"
        )
        expect(insert["name"] as? String == "Desert Dermatology, LLC", "insert name")
        expect(insert["type"] as? String == "customer", "insert type")
        expect(insert["is_active"] as? Bool == true, "insert active")
        expect(insert["contact_name"] as? String == "Jane Q. Smith", "insert contact")
        expect(insert["ticket_prefix"] as? String == "DES", "insert prefix")
        expect(insert["email"] == nil, "empty email omitted")
        expect(insert["created_by"] as? String == "user-1", "created by")

        let parts = CustomerCardPayload.splitPersonName("Dr. Jane Q. Smith")
        expect(parts.first == "Jane" && parts.last == "Q. Smith", "split \(parts)")

        let merged = BusinessCardFields.prefill(
            existing: BusinessCardFields(name: "Old Name", company: "Kept Co", phone: "111"),
            scanned: BusinessCardFields(name: "New Name", phone: "")
        )
        expect(merged.name == "New Name", "merge name")
        expect(merged.company == "Kept Co", "merge company")
        expect(merged.phone == "111", "merge phone kept")

        expect(CardCustomerPage.resolve(URL(string: "https://repairplanet.net/customers")) == .directory, "live directory")
        expect(CardCustomerPage.resolve(URL(string: "https://repairplanet.net/customers/")) == .directory, "live directory slash")
        expect(CardCustomerPage.resolve(URL(string: "https://repairplanet.net/customers/abc-123")) == .profile("abc-123"), "live profile")
        expect(CardCustomerPage.resolve(URL(string: "https://repairplanet.net/customers/abc-123/edit")) == .none, "deeper path ignored")
        expect(CardCustomerPage.resolve(URL(string: "https://repairplanet.net/")) == .none, "home ignored")
        expect(CardCustomerPage.resolve(URL(string: "file:///tmp/customer_directory.html")) == .directory, "bundled directory")
        expect(CardCustomerPage.resolve(URL(string: "file:///tmp/customer_profile.html?id=42")) == .profile("42"), "bundled profile")

        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("card-parser-\(UUID().uuidString)", isDirectory: true)
        let store = CustomerCardDraftStore(directory: directory)
        let draft = CustomerCardDraft(
            id: UUID(),
            mode: .create,
            organizationID: nil,
            needsLink: true,
            fields: classic,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastError: nil,
            pauseAutoRetry: false
        )
        store.upsert(draft)
        let loaded = store.all()
        expect(loaded.count == 1 && loaded[0].fields.company == classic.company, "draft round trip")
        store.remove(id: draft.id)
        expect(store.all().isEmpty, "draft removed")

        if failures.isEmpty {
            print("card-parser: ok")
            return
        }
        for failure in failures {
            fputs(failure + "\n", stderr)
        }
        exit(1)
    }
}
#endif
