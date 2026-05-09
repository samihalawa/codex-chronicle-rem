import AppKit

final class ChronicleREMApp: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let root = NSString(string: "~/.codex/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough").expandingTildeInPath
    private var window: NSWindow!
    private var table = NSTableView()
    private var imageView = NSImageView()
    private var search = NSSearchField()
    private var slider = NSSlider()
    private var titleLabel = NSTextField(labelWithString: "")
    private var playButton = NSButton(title: "Play", target: nil, action: nil)
    private var statusItem: NSStatusItem!
    private var allFrames: [String] = []
    private var frames: [String] = []
    private var currentIndex = 0
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        buildWindow()
        reloadFrames()
        showWindow()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "REM"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Chronicle REM", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Reload", action: #selector(reloadFrames), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Chronicle REM"

        let rootView = NSView()
        window.contentView = rootView

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(split)

        let left = NSView()
        let right = NSView()
        split.addArrangedSubview(left)
        split.addArrangedSubview(right)

        search.placeholderString = "Filter frames"
        search.target = self
        search.action = #selector(applyFilter)
        search.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(search)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("frame")))
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        scroll.documentView = table
        left.addSubview(scroll)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(imageView)

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(controls)

        let prev = NSButton(title: "Prev", target: self, action: #selector(previousFrame))
        let next = NSButton(title: "Next", target: self, action: #selector(nextFrame))
        playButton.target = self
        playButton.action = #selector(togglePlay)
        let reload = NSButton(title: "Reload", target: self, action: #selector(reloadFrames))
        slider.minValue = 0
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false

        controls.addArrangedSubview(prev)
        controls.addArrangedSubview(playButton)
        controls.addArrangedSubview(next)
        controls.addArrangedSubview(reload)
        controls.addArrangedSubview(slider)

        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            split.topAnchor.constraint(equalTo: rootView.topAnchor),
            split.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            left.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            left.widthAnchor.constraint(lessThanOrEqualToConstant: 420),

            search.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            search.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -10),
            search.topAnchor.constraint(equalTo: left.topAnchor, constant: 10),
            search.heightAnchor.constraint(equalToConstant: 28),

            scroll.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: left.bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -12),
            imageView.topAnchor.constraint(equalTo: right.topAnchor, constant: 12),
            imageView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -10),

            controls.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -12),
            controls.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -8),
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),

            titleLabel.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -10),
            titleLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func reloadFrames() {
        let frameRoot = root + "/frames"
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: frameRoot) else {
            allFrames = []
            frames = []
            table.reloadData()
            titleLabel.stringValue = "No archive yet: " + frameRoot
            return
        }

        allFrames = enumerator.compactMap { item in
            guard let rel = item as? String, rel.hasSuffix(".jpg") else { return nil }
            return frameRoot + "/" + rel
        }.sorted()
        applyFilter()
    }

    @objc private func applyFilter() {
        let q = search.stringValue.lowercased()
        frames = q.isEmpty ? allFrames : allFrames.filter { $0.lowercased().contains(q) }
        currentIndex = min(currentIndex, max(frames.count - 1, 0))
        slider.maxValue = Double(max(frames.count - 1, 0))
        table.reloadData()
        showFrame(currentIndex)
    }

    private func showFrame(_ index: Int) {
        guard frames.indices.contains(index) else {
            imageView.image = nil
            titleLabel.stringValue = "No frames"
            return
        }
        currentIndex = index
        slider.doubleValue = Double(index)
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
        imageView.image = NSImage(contentsOfFile: frames[index])
        titleLabel.stringValue = "\(index + 1)/\(frames.count)  " + frames[index]
    }

    @objc private func previousFrame() { showFrame(max(currentIndex - 1, 0)) }
    @objc private func nextFrame() { showFrame(min(currentIndex + 1, max(frames.count - 1, 0))) }
    @objc private func sliderChanged() { showFrame(Int(slider.doubleValue.rounded())) }

    @objc private func togglePlay() {
        if timer != nil {
            timer?.invalidate()
            timer = nil
            playButton.title = "Play"
            return
        }
        playButton.title = "Pause"
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.currentIndex >= self.frames.count - 1 {
                self.showFrame(0)
            } else {
                self.nextFrame()
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { frames.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: URL(fileURLWithPath: frames[row]).lastPathComponent)
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        if row >= 0 { showFrame(row) }
    }
}

let app = NSApplication.shared
let delegate = ChronicleREMApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

