import Foundation

/// Contact fields read from a business card. The photo is not stored.
struct BusinessCardFields: Codable, Equatable, Sendable {
    var name: String
    var title: String
    var company: String
    var phone: String
    var email: String
    var address: String
    var city: String
    var state: String
    var zip: String
    var website: String

    init(
        name: String = "",
        title: String = "",
        company: String = "",
        phone: String = "",
        email: String = "",
        address: String = "",
        city: String = "",
        state: String = "",
        zip: String = "",
        website: String = ""
    ) {
        self.name = name
        self.title = title
        self.company = company
        self.phone = phone
        self.email = email
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.website = website
    }

    var trimmed: BusinessCardFields {
        BusinessCardFields(
            name: name.trimmedCardField,
            title: title.trimmedCardField,
            company: company.trimmedCardField,
            phone: phone.trimmedCardField,
            email: email.trimmedCardField,
            address: address.trimmedCardField,
            city: city.trimmedCardField,
            state: state.trimmedCardField,
            zip: zip.trimmedCardField,
            website: website.trimmedCardField
        )
    }

    var hasAnyValue: Bool {
        let value = trimmed
        return !value.name.isEmpty || !value.title.isEmpty || !value.company.isEmpty
            || !value.phone.isEmpty || !value.email.isEmpty || !value.address.isEmpty
            || !value.city.isEmpty || !value.state.isEmpty || !value.zip.isEmpty
            || !value.website.isEmpty
    }

    /// Existing directory values stay when the scan missed a field.
    static func prefill(existing: BusinessCardFields?, scanned: BusinessCardFields) -> BusinessCardFields {
        let scanned = scanned.trimmed
        guard var base = existing?.trimmed else { return scanned }
        func overlay(_ value: String, _ key: WritableKeyPath<BusinessCardFields, String>) {
            if !value.isEmpty {
                base[keyPath: key] = value
            }
        }
        overlay(scanned.name, \.name)
        overlay(scanned.title, \.title)
        overlay(scanned.company, \.company)
        overlay(scanned.phone, \.phone)
        overlay(scanned.email, \.email)
        overlay(scanned.address, \.address)
        overlay(scanned.city, \.city)
        overlay(scanned.state, \.state)
        overlay(scanned.zip, \.zip)
        overlay(scanned.website, \.website)
        return base
    }

    func bridgeDictionary() -> [String: String] {
        let value = trimmed
        return [
            "name": value.name,
            "title": value.title,
            "company": value.company,
            "phone": value.phone,
            "email": value.email,
            "address": value.address,
            "city": value.city,
            "state": value.state,
            "zip": value.zip,
            "website": value.website
        ]
    }
}

extension String {
    var trimmedCardField: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
