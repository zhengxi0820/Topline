import AppKit

/// 「歌词版本…」轻量列表窗：候选 = 本地 KRC 各版本 + 酷狗搜索 + 网易云搜索。
/// 双击即应用并绑定该版本；「恢复自动匹配」清除绑定回到自动链。
final class VersionsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var versions: [LyricVersion] = []
    private var activeIdProvider: () -> String? = { nil }
    private var onSelect: ((LyricVersion) -> Void)?
    private var onReset: (() -> Void)?

    private let tableView = NSTableView()
    private let hintLabel = NSTextField(labelWithString: "双击使用该版本；搜索进行中…")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "歌词版本"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupContent()
    }

    private func setupContent() {
        let sourceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        sourceColumn.title = "来源"
        sourceColumn.width = 96
        let songColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("song"))
        songColumn.title = "歌曲"
        songColumn.resizingMask = .autoresizingMask
        songColumn.width = 270
        let durationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("duration"))
        durationColumn.title = "时长"
        durationColumn.width = 70
        for column in [sourceColumn, songColumn, durationColumn] {
            tableView.addTableColumn(column)
        }
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 26
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let resetButton = NSButton(title: "恢复自动匹配", target: self, action: #selector(resetClicked))
        resetButton.bezelStyle = .rounded

        let footer = NSStackView(views: [hintLabel, NSView(), resetButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 4, bottom: 4, right: 4)

        let root = NSStackView(views: [scrollView, footer])
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            scrollView.heightAnchor.constraint(equalToConstant: 300),
        ])
        window?.contentView = content
    }

    // MARK: - 对外

    /// loadVersions 在后台拉候选并回调（主线程），activeId 用于打勾
    func show(
        loadVersions: @escaping (@escaping ([LyricVersion]) -> Void) -> Void,
        activeId: @escaping () -> String?,
        onSelect: @escaping (LyricVersion) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.activeIdProvider = activeId
        self.onSelect = onSelect
        self.onReset = onReset
        versions = []
        tableView.reloadData()
        hintLabel.stringValue = "双击使用该版本；搜索进行中…"
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loadVersions { [weak self] list in
            guard let self else { return }
            self.versions = list
            self.tableView.reloadData()
            self.hintLabel.stringValue = list.isEmpty
                ? "没有找到任何候选版本"
                : "双击使用该版本（共 \(list.count) 个）"
        }
    }

    // MARK: - 动作

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < versions.count else { return }
        onSelect?(versions[row])
    }

    @objc private func resetClicked() {
        onReset?()
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        versions.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < versions.count else { return nil }
        let version = versions[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""
        let text: String
        switch identifier {
        case "source":
            let active = version.id == activeIdProvider()
            text = (active ? "✓ " : "") + version.source.rawValue
        case "song":
            text = version.displayTitle
        default:
            text = version.displayDuration
        }
        let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("cell-\(identifier)"), owner: self
        ) as? NSTextField ?? {
            let field = NSTextField(labelWithString: "")
            field.identifier = NSUserInterfaceItemIdentifier("cell-\(identifier)")
            field.lineBreakMode = .byTruncatingMiddle
            field.cell?.wraps = false
            return field
        }()
        cell.stringValue = text
        return cell
    }
}
