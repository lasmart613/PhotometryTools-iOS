import SwiftUI

@MainActor
final class CardConfirmModel: ObservableObject {
    @Published var fields: BusinessCardFields
    @Published var errorMessage: String?
    @Published var isSaving = false
    let mode: CardCustomerMode
    let notice: String

    var onCancel: () -> Void = {}
    var onRetake: () -> Void = {}
    var onSave: (BusinessCardFields) -> Void = { _ in }

    init(fields: BusinessCardFields, mode: CardCustomerMode, notice: String) {
        self.fields = fields
        self.mode = mode
        self.notice = notice
    }

    var canSave: Bool {
        let value = fields.trimmed
        if isSaving { return false }
        if mode == .create { return !value.company.isEmpty }
        return value.hasAnyValue
    }

    func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        onSave(fields.trimmed)
    }
}

struct CardConfirmView: View {
    @ObservedObject var model: CardConfirmModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("From the card") {
                    TextField("Name", text: $model.fields.name)
                        .textContentType(.name)
                    TextField("Title", text: $model.fields.title)
                        .textContentType(.jobTitle)
                    TextField("Company", text: $model.fields.company)
                        .textContentType(.organizationName)
                    TextField("Phone", text: $model.fields.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $model.fields.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Address", text: $model.fields.address)
                        .textContentType(.fullStreetAddress)
                    TextField("City", text: $model.fields.city)
                        .textContentType(.addressCity)
                    TextField("State", text: $model.fields.state)
                        .textContentType(.addressState)
                    TextField("ZIP", text: $model.fields.zip)
                        .textContentType(.postalCode)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Website", text: $model.fields.website)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(model.mode == .create
                         ? "Company is the customer name in your directory. Nothing is saved until you tap Save."
                         : "Empty fields on an existing customer are left as they are. Nothing is saved until you tap Save.")
                }

                if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(model.mode == .create ? "New customer" : "Update customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.onCancel)
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "Saving…" : "Save", action: model.save)
                        .disabled(!model.canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Retake photo", action: model.onRetake)
                    .disabled(model.isSaving)
                    .padding(.bottom, 8)
            }
        }
    }
}
