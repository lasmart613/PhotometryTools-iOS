import SwiftUI

/// Live Total Service Pro site. Bundled HTML loads only when the device is offline.
struct HomeView: View {
    @ObservedObject private var cards = CardScanCenter.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TSPWebView(entry: .liveSite)
            if showsCardChrome {
                cardChrome
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            cards.refreshDraftCount()
        }
    }

    private var showsCardChrome: Bool {
        cards.banner != nil || cards.pendingCount > 0 || (cards.page.scanTitle != nil && !cards.inPageButtonVisible)
    }

    private var cardChrome: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let banner = cards.banner {
                Text(banner)
                    .font(.footnote)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { cards.clearBanner() }
            }
            if cards.pendingCount > 0 {
                Button {
                    Task { await CustomerCardDraftSync.shared.flush(manual: true) }
                } label: {
                    Text(cards.pendingCount == 1 ? "Sync 1 card draft" : "Sync \(cards.pendingCount) card drafts")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            if let title = cards.page.scanTitle, !cards.inPageButtonVisible {
                Button {
                    Task { await startScan() }
                } label: {
                    Label(title, systemImage: "text.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(title == "Update from card" ? "updateFromCardButton" : "scanCardButton")
            }
        }
    }

    private func startScan() async {
        let request: CardScanRequest
        switch cards.page {
        case .directory:
            request = CardScanRequest(mode: .create, organizationID: nil)
        case .profile(let id):
            request = CardScanRequest(mode: .update, organizationID: id)
        case .none:
            return
        }
        _ = await CardScanFlow.start(request)
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthService.shared)
        .environmentObject(BiometricSettings.shared)
        .environmentObject(BiometricUnlockController.shared)
}
