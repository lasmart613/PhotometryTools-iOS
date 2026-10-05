import AVFoundation
import SwiftUI
import UIKit

struct CardScanRequest: Equatable, Sendable {
    var mode: CardCustomerMode
    var organizationID: String?

    static func from(
        payload: [String: Any],
        pageURL: URL?,
        notedPage: CardCustomerPage = .none
    ) -> CardScanRequest {
        let page = CardCustomerPage.resolve(pageURL)
        let mode = (payload["mode"] as? String)?.lowercased() ?? ""
        let explicitID = firstString(payload["organizationId"])
            ?? firstString(payload["organization_id"])
            ?? firstString(payload["id"])
        let profileID = page.profileID ?? (page == .none ? notedPage.profileID : nil)
        if mode == "update" || (mode.isEmpty && profileID != nil) {
            let id = explicitID ?? profileID
            return CardScanRequest(mode: .update, organizationID: id)
        }
        return CardScanRequest(mode: .create, organizationID: nil)
    }

    private static func firstString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmedCardField
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CardScanOutcome: Equatable {
    var saved: Bool
    var queued: Bool
    var organizationID: String?
    var fields: BusinessCardFields

    var bridgeValue: [String: Any] {
        [
            "saved": saved,
            "queued": queued,
            "organizationId": organizationID ?? "",
            "fields": fields.bridgeDictionary()
        ]
    }
}

enum CardScanError: LocalizedError {
    case cancelled
    case busy
    case cameraUnavailable
    case cameraDenied

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Cancelled"
        case .busy:
            return "A card scan is already open."
        case .cameraUnavailable:
            return "A camera is required to scan a business card."
        case .cameraDenied:
            return "Camera access is off. Enable the camera in Settings to scan business cards into customer contact fields."
        }
    }
}

@MainActor
enum CardScanFlow {
    private static var busy = false
    private static var cameraPicker: CardCameraPicker?

    static func start(_ request: CardScanRequest) async -> Result<CardScanOutcome, Error> {
        guard !busy else { return .failure(CardScanError.busy) }
        busy = true
        defer { busy = false }
        return await run(request)
    }

    private static func run(_ request: CardScanRequest) async -> Result<CardScanOutcome, Error> {
        let box = DraftBox(CustomerCardDraft(
            id: UUID(),
            mode: request.mode,
            organizationID: request.mode == .update ? request.organizationID : nil,
            needsLink: request.mode == .create,
            fields: BusinessCardFields(),
            createdAt: Date(),
            lastError: nil,
            pauseAutoRetry: false
        ))

        while true {
            switch await capturePhoto() {
            case .cancelled:
                return .failure(CardScanError.cancelled)
            case .unavailable:
                presentAlert(title: "Camera needed", message: CardScanError.cameraUnavailable.localizedDescription)
                return .failure(CardScanError.cameraUnavailable)
            case .denied:
                presentAlert(title: "Camera access", message: CardScanError.cameraDenied.localizedDescription)
                return .failure(CardScanError.cameraDenied)
            case .photo(let image):
                let scanned: BusinessCardFields
                let ocrFailed: Bool
                do {
                    scanned = try BusinessCardOCR.recognize(image: image)
                    ocrFailed = !scanned.hasAnyValue
                } catch {
                    scanned = BusinessCardFields()
                    ocrFailed = true
                }
                var existing: BusinessCardFields?
                if request.mode == .update, let id = request.organizationID, CustomerCardDraftSync.shared.isOnline {
                    existing = await CustomerCardRepository.fetchFields(organizationID: id)
                }
                let prefill = BusinessCardFields.prefill(existing: existing, scanned: scanned)
                let notice = ocrFailed
                    ? "No text was recognized on this device. Type the customer details or retake the photo. Nothing is saved until you tap Save."
                    : "Review the fields read on this device. Nothing is saved until you tap Save."
                switch await confirm(fields: prefill, mode: request.mode, notice: notice, box: box) {
                case .cancel:
                    return .failure(CardScanError.cancelled)
                case .retake:
                    continue
                case .finished(let outcome):
                    return .success(outcome)
                }
            }
        }
    }

    fileprivate enum ConfirmStep {
        case cancel
        case retake
        case finished(CardScanOutcome)
    }

    private static func confirm(
        fields: BusinessCardFields,
        mode: CardCustomerMode,
        notice: String,
        box: DraftBox
    ) async -> ConfirmStep {
        let model = CardConfirmModel(fields: fields, mode: mode, notice: notice)
        let host = UIHostingController(rootView: CardConfirmView(model: model))
        host.modalPresentationStyle = .pageSheet
        guard let presenter = PDFHost.topViewController() else {
            return .cancel
        }

        return await withCheckedContinuation { continuation in
            let gate = ResumeGate(continuation)
            let watcher = SheetDismissWatcher { gate.resume(.cancel) }
            watcher.allowDismiss = { !model.isSaving }
            host.presentationController?.delegate = watcher
            model.onCancel = { [watcher] in
                _ = watcher
                guard !model.isSaving else { return }
                host.dismiss(animated: true) {
                    gate.resume(.cancel)
                }
            }
            model.onRetake = {
                guard !model.isSaving else { return }
                host.dismiss(animated: true) {
                    gate.resume(.retake)
                }
            }
            model.onSave = { edited in
                box.draft.fields = edited
                Task {
                    let outcome = await persist(box: box)
                    switch outcome {
                    case .stay(let message):
                        model.isSaving = false
                        model.errorMessage = message
                    case .done(let result):
                        host.dismiss(animated: true) {
                            gate.resume(.finished(result))
                        }
                    }
                }
            }
            presenter.present(host, animated: true)
            host.presentationController?.delegate = watcher
        }
    }

    private enum PersistStep {
        case stay(String)
        case done(CardScanOutcome)
    }

    private static func persist(box: DraftBox) async -> PersistStep {
        if !CustomerCardDraftSync.shared.isOnline {
            box.draft.lastError = "Waiting for a network connection."
            box.draft.pauseAutoRetry = false
            CustomerCardDraftStore.shared.upsert(box.draft)
            CardScanCenter.shared.refreshDraftCount()
            let outcome = CardScanOutcome(saved: false, queued: true, organizationID: box.draft.organizationID, fields: box.draft.fields)
            presentAlert(
                title: "Saved on this device",
                message: "This customer is queued on the device. It will sync to your directory when a connection is available."
            )
            return .done(outcome)
        }

        let result = await CustomerCardRepository.commit(box.draft)
        switch result {
        case .finished(let updated):
            box.draft = updated
            CustomerCardDraftStore.shared.remove(id: updated.id)
            CardScanCenter.shared.refreshDraftCount()
            CardScanCenter.shared.reloadWebPage?()
            presentAlert(
                title: updated.mode == .create ? "Customer saved" : "Customer updated",
                message: "Saved from the card you confirmed. The customer page will refresh."
            )
            return .done(CardScanOutcome(
                saved: true,
                queued: false,
                organizationID: updated.organizationID,
                fields: updated.fields
            ))
        case .failed(let updated, let error):
            box.draft = updated
            if error.shouldQueue || updated.organizationID != nil {
                var kept = updated
                kept.lastError = error.message
                kept.pauseAutoRetry = !error.shouldQueue
                CustomerCardDraftStore.shared.upsert(kept)
                CardScanCenter.shared.refreshDraftCount()
                if error.shouldQueue {
                    presentAlert(title: "Saved on this device", message: error.message)
                    return .done(CardScanOutcome(
                        saved: false,
                        queued: true,
                        organizationID: kept.organizationID,
                        fields: kept.fields
                    ))
                }
            }
            return .stay(error.message)
        }
    }

    private enum Capture {
        case photo(UIImage)
        case cancelled
        case unavailable
        case denied
    }

    private static func capturePhoto() async -> Capture {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .unavailable
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { return .denied }
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
        let picker = CardCameraPicker()
        cameraPicker = picker
        let image = await picker.capture()
        cameraPicker = nil
        if let image { return .photo(image) }
        return .cancelled
    }

    private static func presentAlert(title: String, message: String) {
        PDFHost.presentAlert(title: title, message: message)
    }
}

private final class DraftBox {
    var draft: CustomerCardDraft
    init(_ draft: CustomerCardDraft) { self.draft = draft }
}

private final class SheetDismissWatcher: NSObject, UIAdaptivePresentationControllerDelegate {
    var allowDismiss: () -> Bool = { true }
    private let onDismiss: () -> Void
    init(_ onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        allowDismiss()
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDismiss()
    }
}

private final class ResumeGate: @unchecked Sendable {
    private var resumed = false
    private let continuation: CheckedContinuation<CardScanFlow.ConfirmStep, Never>

    init(_ continuation: CheckedContinuation<CardScanFlow.ConfirmStep, Never>) {
        self.continuation = continuation
    }

    func resume(_ step: CardScanFlow.ConfirmStep) {
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: step)
    }
}

@MainActor
private final class CardCameraPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private var continuation: CheckedContinuation<UIImage?, Never>?

    func capture() async -> UIImage? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.delegate = self
            picker.modalPresentationStyle = .fullScreen
            guard let host = PDFHost.topViewController() else {
                finish(nil)
                return
            }
            host.present(picker, animated: true)
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in
            picker.dismiss(animated: true) { self.finish(nil) }
        }
    }

    nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = info[.originalImage] as? UIImage
        Task { @MainActor in
            picker.dismiss(animated: true) { self.finish(image) }
        }
    }

    private func finish(_ image: UIImage?) {
        continuation?.resume(returning: image)
        continuation = nil
    }
}
