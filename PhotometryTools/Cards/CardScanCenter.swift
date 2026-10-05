import Foundation
import Network

@MainActor
final class CardScanCenter: ObservableObject {
    static let shared = CardScanCenter()

    @Published var page: CardCustomerPage = .none
    @Published var inPageButtonVisible = false
    @Published var pendingCount = 0
    @Published var banner: String?

    var reloadWebPage: (() -> Void)?

    func note(url: URL?) {
        let next = CardCustomerPage.resolve(url)
        if next != page {
            page = next
        }
    }

    func noteInPageButton(_ visible: Bool) {
        if inPageButtonVisible != visible {
            inPageButtonVisible = visible
        }
    }

    func refreshDraftCount() {
        pendingCount = CustomerCardDraftStore.shared.all().count
    }

    func noteSyncSuccess(count: Int) {
        guard count > 0 else { return }
        banner = count == 1
            ? "A scanned customer synced to your directory."
            : "\(count) scanned customers synced to your directory."
        refreshDraftCount()
        reloadWebPage?()
    }

    func clearBanner() {
        banner = nil
    }
}

@MainActor
final class CustomerCardDraftSync {
    static let shared = CustomerCardDraftSync()

    private var started = false
    private var flushing = false
    private var online = true
    private var resolved = false
    private let monitor = NWPathMonitor()

    var isOnline: Bool { resolved ? online : true }

    func start() {
        guard !started else { return }
        started = true
        CardScanCenter.shared.refreshDraftCount()
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                CustomerCardDraftSync.shared.handle(online: satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "tsp.card.network"))
    }

    func flush(manual: Bool = false) async {
        guard !flushing else { return }
        guard AuthService.shared.isSignedIn else { return }
        flushing = true
        defer {
            flushing = false
            CardScanCenter.shared.refreshDraftCount()
        }

        guard isOnline else { return }
        var synced = 0
        for draft in CustomerCardDraftStore.shared.all() {
            if draft.pauseAutoRetry && !manual { continue }
            var next = draft
            if manual { next.pauseAutoRetry = false }
            let result = await CustomerCardRepository.commit(next)
            switch result {
            case .finished:
                CustomerCardDraftStore.shared.remove(id: next.id)
                synced += 1
            case .failed(let updated, let error):
                var kept = updated
                kept.lastError = error.message
                kept.pauseAutoRetry = !error.shouldQueue
                CustomerCardDraftStore.shared.upsert(kept)
                if error.shouldQueue {
                    CardScanCenter.shared.banner = error.message
                    break
                }
            }
        }
        if synced > 0 {
            CardScanCenter.shared.noteSyncSuccess(count: synced)
        }
    }

    private func handle(online satisfied: Bool) {
        let wasOnline = resolved && online
        online = satisfied
        resolved = true
        guard satisfied, !wasOnline else { return }
        Task { await flush(manual: false) }
    }
}
