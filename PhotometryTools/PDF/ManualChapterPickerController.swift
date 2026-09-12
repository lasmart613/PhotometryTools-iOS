import UIKit

/// Folder-manual chapter grid equivalent from Android `pdf_viewer.html`.
final class ManualChapterPickerController: UITableViewController {
    private let chapters: [ManualURLClient.Chapter]
    private let onPick: (ManualURLClient.Chapter) -> Void

    init(chapters: [ManualURLClient.Chapter], title: String, onPick: @escaping (ManualURLClient.Chapter) -> Void) {
        self.chapters = chapters
        self.onPick = onPick
        super.init(style: .insetGrouped)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "chapter")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chapters.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chapter", for: indexPath)
        let chapter = chapters[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = chapter.title
        config.secondaryText = chapter.order == 99 ? nil : "Chapter \(chapter.order)"
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let chapter = chapters[indexPath.row]
        dismiss(animated: true) { [onPick] in
            onPick(chapter)
        }
    }
}
