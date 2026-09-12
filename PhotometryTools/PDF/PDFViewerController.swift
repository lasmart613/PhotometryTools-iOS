import PDFKit
import UIKit

/// In-app PDFKit viewer with a share-sheet action (UIActivityViewController).
final class PDFViewerController: UIViewController {
    private let fileURL: URL
    private let documentTitle: String
    private let pdfView = PDFView()
    private let presentShareOnAppear: Bool

    init(fileURL: URL, title: String, presentShareOnAppear: Bool = false) {
        self.fileURL = fileURL
        self.documentTitle = title
        self.presentShareOnAppear = presentShareOnAppear
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        view.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if let document = PDFDocument(url: fileURL) {
            pdfView.document = document
        } else {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "This PDF could not be opened."
            label.textAlignment = .center
            label.numberOfLines = 0
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
            ])
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(share)
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if presentShareOnAppear {
            share()
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc func share() {
        PDFHost.presentShareSheet(fileURL: fileURL, title: documentTitle, from: self)
    }
}

@MainActor
enum PDFHost {
    static func topViewController(from start: UIViewController? = nil) -> UIViewController? {
        let root = start
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        return uppermost(from: root)
    }

    private static func uppermost(from controller: UIViewController?) -> UIViewController? {
        if let presented = controller?.presentedViewController {
            return uppermost(from: presented)
        }
        if let nav = controller as? UINavigationController {
            return uppermost(from: nav.visibleViewController)
        }
        if let tabs = controller as? UITabBarController {
            return uppermost(from: tabs.selectedViewController)
        }
        return controller
    }

    static func presentViewer(fileURL: URL, title: String, shareImmediately: Bool = false) {
        guard let host = topViewController() else { return }
        let viewer = PDFViewerController(fileURL: fileURL, title: title, presentShareOnAppear: shareImmediately)
        let nav = UINavigationController(rootViewController: viewer)
        nav.modalPresentationStyle = .fullScreen
        host.present(nav, animated: true)
    }

    static func presentShareSheet(fileURL: URL, title: String, from controller: UIViewController? = nil) {
        guard let host = controller ?? topViewController() else { return }
        let item = PDFActivityItem(url: fileURL, title: title)
        let activity = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        if let pop = activity.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        host.present(activity, animated: true)
    }

    static func presentChapters(_ chapters: [ManualURLClient.Chapter], title: String, onPick: @escaping (ManualURLClient.Chapter) -> Void) {
        guard let host = topViewController() else { return }
        let picker = ManualChapterPickerController(chapters: chapters, title: title, onPick: onPick)
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        host.present(nav, animated: true)
    }

    static func presentAlert(title: String, message: String) {
        guard let host = topViewController() else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        host.present(alert, animated: true)
    }
}

/// Names the shared file in the iOS share sheet.
private final class PDFActivityItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "com.adobe.pdf"
    }
}
