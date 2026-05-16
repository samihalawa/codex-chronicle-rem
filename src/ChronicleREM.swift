import AppKit
import SwiftUI

struct FrameItem: Identifiable, Hashable {
    let url: URL

    var id: String { url.path }
    var filename: String { url.lastPathComponent }
    var searchableText: String { url.path.lowercased() }

    func image() -> NSImage? {
        NSImage(contentsOf: url)
    }
}

enum ChronicleAppIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        let rounded = NSBezierPath(roundedRect: bounds.insetBy(dx: 40, dy: 40), xRadius: 230, yRadius: 230)
        NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.11, alpha: 1).setFill()
        rounded.fill()

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.09, green: 0.18, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.56, blue: 0.68, alpha: 1),
            NSColor(calibratedRed: 0.70, green: 0.24, blue: 0.60, alpha: 1)
        ])!
        gradient.draw(in: rounded, angle: 35)

        let innerGlow = NSBezierPath(roundedRect: bounds.insetBy(dx: 112, dy: 112), xRadius: 180, yRadius: 180)
        NSColor.white.withAlphaComponent(0.10).setFill()
        innerGlow.fill()

        let ring = NSBezierPath(ovalIn: NSRect(x: 228, y: 228, width: 568, height: 568))
        NSColor.white.withAlphaComponent(0.18).setStroke()
        ring.lineWidth = 24
        ring.stroke()

        if let symbol = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Chronicle REM") {
            let configured = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 460, weight: .semibold, scale: .large)
            ) ?? symbol
            NSColor.white.set()
            configured.draw(in: NSRect(x: 282, y: 282, width: 460, height: 460))
        }

        let spark = NSBezierPath()
        spark.move(to: NSPoint(x: 360, y: 308))
        spark.curve(
            to: NSPoint(x: 650, y: 690),
            controlPoint1: NSPoint(x: 390, y: 520),
            controlPoint2: NSPoint(x: 560, y: 650)
        )
        NSColor.white.withAlphaComponent(0.16).setStroke()
        spark.lineWidth = 20
        spark.lineCapStyle = .round
        spark.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

final class ChronicleArchiveStore: ObservableObject {
    static let shared = ChronicleArchiveStore()

    private let archiveRoot = URL(
        fileURLWithPath: NSString(
            string: "~/.codex/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough"
        ).expandingTildeInPath,
        isDirectory: true
    )

    @Published var allFrames: [FrameItem] = []
    @Published var frames: [FrameItem] = []
    @Published var searchText = "" {
        didSet { applyFilter() }
    }
    @Published var selectedIndex: Int? = nil
    @Published var isPlaying = false
    @Published var statusMessage = "Loading archive..."

    private var playbackTimer: Timer?

    var selectedFrame: FrameItem? {
        guard let selectedIndex, frames.indices.contains(selectedIndex) else { return nil }
        return frames[selectedIndex]
    }

    var sidebarSummary: String {
        if allFrames.isEmpty {
            return "No archive found yet"
        }
        return "\(frames.count) visible · \(allFrames.count) archived"
    }

    var toolbarSubtitle: String {
        if allFrames.isEmpty {
            return "Waiting for archived frames"
        }
        return "\(frames.count) visible · \(allFrames.count) archived"
    }

    var playbackSummary: String {
        guard let selectedIndex, frames.indices.contains(selectedIndex), !frames.isEmpty else {
            return "0 / 0"
        }
        return "\(selectedIndex + 1) / \(frames.count)"
    }

    var sliderRange: ClosedRange<Double> {
        0...Double(max(frames.count - 1, 0))
    }

    var sliderValue: Double {
        Double(selectedIndex ?? 0)
    }

    var archiveRootPath: String {
        archiveRoot.appendingPathComponent("frames", isDirectory: true).path
    }

    func reloadFrames() {
        let frameRoot = archiveRoot.appendingPathComponent("frames", isDirectory: true)
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: frameRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            allFrames = []
            frames = []
            selectedIndex = nil
            statusMessage = "No archive yet at \(frameRoot.path)"
            stopPlayback()
            return
        }

        let discovered = enumerator.compactMap { element -> FrameItem? in
            guard let url = element as? URL else { return nil }
            guard url.pathExtension.lowercased() == "jpg" else { return nil }
            return FrameItem(url: url)
        }

        allFrames = discovered.sorted { lhs, rhs in
            lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
        applyFilter()
    }

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        frames = query.isEmpty ? allFrames : allFrames.filter { $0.searchableText.contains(query) }

        if frames.isEmpty {
            selectedIndex = nil
            statusMessage = allFrames.isEmpty
                ? "No archived frames yet"
                : "No frames match \"\(searchText)\""
            stopPlayback()
            return
        }

        if let selectedIndex {
            self.selectedIndex = min(selectedIndex, frames.count - 1)
        } else {
            selectedIndex = 0
        }

        statusMessage = "\(frames.count) frames available"
    }

    func select(index: Int) {
        guard !frames.isEmpty else {
            selectedIndex = nil
            statusMessage = "No frames to display"
            stopPlayback()
            return
        }

        let clamped = min(max(index, 0), frames.count - 1)
        selectedIndex = clamped
        statusMessage = "\(frames.count) frames available"
    }

    func previousFrame() {
        guard let selectedIndex else {
            select(index: 0)
            return
        }
        select(index: selectedIndex - 1)
    }

    func nextFrame() {
        guard let selectedIndex else {
            select(index: 0)
            return
        }
        select(index: selectedIndex + 1)
    }

    func togglePlayback() {
        if playbackTimer != nil {
            stopPlayback()
            return
        }

        guard !frames.isEmpty else { return }
        if selectedIndex == nil {
            selectedIndex = 0
        }

        isPlaying = true
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            self?.advancePlayback()
        }
    }

    private func advancePlayback() {
        guard !frames.isEmpty else {
            stopPlayback()
            return
        }

        let next = (selectedIndex ?? -1) + 1
        if next >= frames.count {
            selectedIndex = 0
        } else {
            selectedIndex = next
        }
    }

    private func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
    }
}

struct ChronicleRootView: View {
    @ObservedObject var model: ChronicleArchiveStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $compactColumn
        ) {
            SidebarView(model: model)
        } detail: {
            ChronicleDetailView(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Filter frames")
        .searchToolbarBehavior(.automatic)
        .toolbar {
            ToolbarSpacer()

            ToolbarItem(placement: .primaryAction) {
                Button(action: model.reloadFrames) {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct SidebarView: View {
    @ObservedObject var model: ChronicleArchiveStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedIndex) {
                Section {
                    ForEach(Array(model.frames.enumerated()), id: \.offset) { index, frame in
                        FrameRow(frame: frame, isSelected: model.selectedIndex == index)
                            .tag(index)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Archived Frames")
                            .font(.headline)
                        Text(model.sidebarSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .textCase(nil)
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
    }
}

struct FrameRow: View {
    let frame: FrameItem
    let isSelected: Bool

    var body: some View {
        Label {
            Text(frame.filename)
                .lineLimit(1)
                .truncationMode(.middle)
                .fontWeight(isSelected ? .semibold : .regular)
        } icon: {
            Image(systemName: "photo")
        }
    }
}

struct ChronicleDetailView: View {
    @ObservedObject var model: ChronicleArchiveStore

    var body: some View {
        ZStack {
            backgroundLayer

            if let frame = model.selectedFrame, let image = frame.image() {
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 24) {
                        Spacer(minLength: 8)

                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
                            .backgroundExtensionEffect()

                        Text(frame.filename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity, minHeight: 560, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PlaybackGlassBar(model: model)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                }
            } else {
                ContentUnavailableView {
                    Label("No frame selected", systemImage: "photo.on.rectangle")
                } description: {
                    Text(model.statusMessage)
                } actions: {
                    Button("Reload archive") {
                        model.reloadFrames()
                    }
                }
                .padding(24)
            }
        }
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.18),
                Color.clear,
                Color.accentColor.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [
                    Color.white.opacity(0.14),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 80,
                endRadius: 520
            )
        }
        .backgroundExtensionEffect()
    }
}

struct PlaybackGlassBar: View {
    @ObservedObject var model: ChronicleArchiveStore

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { model.sliderValue },
            set: { model.select(index: Int($0.rounded())) }
        )
    }

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.selectedFrame?.filename ?? "No frame selected")
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(model.playbackSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 12)

                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: 10) {
                    Button(action: model.previousFrame) {
                        Label("Previous", systemImage: "backward.fill")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)

                    Button(action: model.togglePlayback) {
                        Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)

                    Button(action: model.nextFrame) {
                        Label("Next", systemImage: "forward.fill")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)

                    Button(action: model.reloadFrames) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)

                    Spacer(minLength: 12)

                    Slider(value: sliderBinding, in: model.sliderRange, step: 1)
                        .disabled(model.frames.isEmpty)
                        .frame(minWidth: 280)
                }
            }
            .padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

final class ChronicleREMAppDelegate: NSObject, NSApplicationDelegate {
    private let store = ChronicleArchiveStore.shared
    private var statusItem: NSStatusItem!
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = ChronicleAppIcon.make()
        buildMainMenu()
        buildStatusItem()
        buildWindow()
        store.reloadFrames()
        showWindow()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "REM"

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Chronicle REM", action: #selector(showWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reloadFrames), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let playItem = NSMenuItem(title: "Play / Pause", action: #selector(togglePlayback), keyEquivalent: "p")
        playItem.target = self
        menu.addItem(playItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Chronicle REM")

        let aboutItem = NSMenuItem(title: "About Chronicle REM", action: #selector(showAboutPanel), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: "Hide Chronicle REM", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.target = NSApp
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)

        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Chronicle REM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")

        let minimizeItem = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(zoomItem)

        let closeItem = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(closeItem)

        windowMenuItem.submenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        let rootView = ChronicleRootView(model: store)
        let hostingController = NSHostingController(rootView: rootView)

        window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "Chronicle REM"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1024, height: 640)
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()
        window.setFrame(NSRect(x: 120, y: 120, width: 1180, height: 760), display: false)
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func reloadFrames() {
        store.reloadFrames()
    }

    @objc private func togglePlayback() {
        store.togglePlayback()
    }

    @objc private func showAboutPanel() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Chronicle REM",
            .applicationVersion: "0.1"
        ])
    }
}

let app = NSApplication.shared
let delegate = ChronicleREMAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
