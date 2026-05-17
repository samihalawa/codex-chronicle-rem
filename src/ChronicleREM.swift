import AppKit
import Darwin
import SwiftUI

struct FrameItem: Identifiable, Hashable {
    let url: URL
    let fileSize: Int64?
    let modificationDate: Date?

    var id: String { url.path }
    var filename: String { url.lastPathComponent }
    var searchableText: String { url.path.lowercased() }

    private static let metadataDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter
    }()

    init(url: URL) {
        self.url = url
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        self.fileSize = values?.fileSize.map(Int64.init)
        self.modificationDate = values?.contentModificationDate
    }

    func image() -> NSImage? {
        NSImage(contentsOf: url)
    }

    var metadataSummary: String {
        var parts: [String] = []

        if let fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }

        if let modificationDate {
            parts.append(Self.metadataDateFormatter.string(from: modificationDate))
        }

        return parts.isEmpty ? "No file metadata" : parts.joined(separator: " · ")
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

private struct ChronicleGlassBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.18),
                Color.clear,
                Color.accentColor.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [
                    Color.white.opacity(0.16),
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

private struct ChronicleGlassCard<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

final class ChronicleArchiveStore: ObservableObject {
    static let shared = ChronicleArchiveStore()

    private enum DefaultsKey {
        static let searchText = "ChronicleREM.searchText"
        static let selectedIndex = "ChronicleREM.selectedIndex"
    }

    private let archiveRoot = URL(
        fileURLWithPath: NSString(
            string: "~/.codex/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough"
        ).expandingTildeInPath,
        isDirectory: true
    )

    private var pendingRestoredSelectionIndex: Int?
    private var pendingArchiveMonitorReload: DispatchWorkItem?
    private var archiveMonitor: DispatchSourceFileSystemObject?

    @Published var allFrames: [FrameItem] = []
    @Published var frames: [FrameItem] = []
    @Published var searchText = "" {
        didSet {
            UserDefaults.standard.set(searchText, forKey: DefaultsKey.searchText)
            applyFilter()
        }
    }
    @Published var selectedIndex: Int? = nil {
        didSet {
            if let selectedIndex {
                UserDefaults.standard.set(selectedIndex, forKey: DefaultsKey.selectedIndex)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.selectedIndex)
            }
        }
    }
    @Published var shouldFocusSearchField = false
    @Published var isPlaying = false
    @Published var statusMessage = "Loading archive..."

    private var playbackTimer: Timer?

    init() {
        searchText = UserDefaults.standard.string(forKey: DefaultsKey.searchText) ?? ""

        if UserDefaults.standard.object(forKey: DefaultsKey.selectedIndex) != nil {
            pendingRestoredSelectionIndex = UserDefaults.standard.integer(forKey: DefaultsKey.selectedIndex)
        }
    }

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

    var archiveFramesURL: URL {
        archiveRoot.appendingPathComponent("frames", isDirectory: true)
    }

    var archiveFramesPath: String {
        archiveFramesURL.path
    }

    var selectedFramePath: String? {
        selectedFrame?.url.path
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

    func reloadFrames() {
        let frameRoot = archiveFramesURL
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
        refreshArchiveMonitor()
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

        if let pendingRestoredSelectionIndex {
            self.pendingRestoredSelectionIndex = nil
            selectedIndex = min(pendingRestoredSelectionIndex, frames.count - 1)
            statusMessage = "\(frames.count) frames available"
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

    func openArchiveFolder() {
        NSWorkspace.shared.open(archiveFramesURL)
        statusMessage = "Opened archive folder"
    }

    func revealSelectedInFinder() {
        guard let selectedFrame else {
            statusMessage = "No selected frame to reveal"
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([selectedFrame.url])
        statusMessage = "Revealed \(selectedFrame.filename) in Finder"
    }

    func openSelectedInDefaultApp() {
        guard let selectedFrame else {
            statusMessage = "No selected frame to open"
            return
        }

        NSWorkspace.shared.open(selectedFrame.url)
        statusMessage = "Opened \(selectedFrame.filename)"
    }

    func copySelectedPath() {
        guard let selectedFramePath else {
            statusMessage = "No selected frame to copy"
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedFramePath, forType: .string)
        statusMessage = "Copied selected frame path"
    }

    func copySelectedFilename() {
        guard let selectedFrame else {
            statusMessage = "No selected frame to copy"
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedFrame.filename, forType: .string)
        statusMessage = "Copied selected frame name"
    }

    func clearSelection() {
        selectedIndex = nil
        statusMessage = "Selection cleared"
    }

    func requestSearchFocus() {
        shouldFocusSearchField = true
    }

    private func refreshArchiveMonitor() {
        stopArchiveMonitor()

        let frameRoot = archiveFramesURL.path
        let fd = open(frameRoot, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.scheduleArchiveReload()
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.resume()
        archiveMonitor = source
    }

    private func stopArchiveMonitor() {
        pendingArchiveMonitorReload?.cancel()
        pendingArchiveMonitorReload = nil

        archiveMonitor?.cancel()
        archiveMonitor = nil
    }

    private func scheduleArchiveReload() {
        pendingArchiveMonitorReload?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.reloadFrames()
        }
        pendingArchiveMonitorReload = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
}

struct ChronicleRootView: View {
    @ObservedObject var model: ChronicleArchiveStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @FocusState private var searchFieldFocused: Bool

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
        .searchFocused($searchFieldFocused)
        .searchToolbarBehavior(.automatic)
        .onChange(of: model.shouldFocusSearchField) { _, shouldFocus in
            guard shouldFocus else { return }
            searchFieldFocused = true
            model.shouldFocusSearchField = false
        }
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

                        Text(frame.metadataSummary)
                            .font(.caption2)
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

struct ChroniclePreferencesView: View {
    @ObservedObject var model: ChronicleArchiveStore

    var body: some View {
        ZStack {
            ChronicleGlassBackdrop()

            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(alignment: .leading, spacing: 18) {
                        ChronicleGlassCard(title: "Archive") {
                            VStack(alignment: .leading, spacing: 10) {
                                LabeledContent("Folder") {
                                    Text(model.archiveFramesPath)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }

                                LabeledContent("Frames") {
                                    Text("\(model.allFrames.count)")
                                        .monospacedDigit()
                                }

                                HStack(spacing: 12) {
                                    Button("Open Archive Folder") {
                                        model.openArchiveFolder()
                                    }
                                    .buttonStyle(.glassProminent)

                                    Button("Reveal Selected in Finder") {
                                        model.revealSelectedInFinder()
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(model.selectedFrame == nil)

                                    Button("Open Selected") {
                                        model.openSelectedInDefaultApp()
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(model.selectedFrame == nil)
                                }
                            }
                        }

                        ChronicleGlassCard(title: "Selection") {
                            VStack(alignment: .leading, spacing: 10) {
                                LabeledContent("Current frame") {
                                    Text(model.selectedFrame?.filename ?? "None")
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                HStack(spacing: 12) {
                                    Button("Copy Selected Path") {
                                        model.copySelectedPath()
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(model.selectedFrame == nil)

                                    Button("Copy Selected Name") {
                                        model.copySelectedFilename()
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(model.selectedFrame == nil)

                                    Button("Clear Selection") {
                                        model.clearSelection()
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(model.selectedFrame == nil)
                                }
                            }
                        }

                        ChronicleGlassCard(title: "Shortcuts") {
                            VStack(alignment: .leading, spacing: 6) {
                                ShortcutRow(action: "Find", shortcut: "⌘F")
                                ShortcutRow(action: "Reload", shortcut: "⌘R")
                                ShortcutRow(action: "Open Archive Folder", shortcut: "⌘O")
                                ShortcutRow(action: "Preferences", shortcut: "⌘,")
                                ShortcutRow(action: "Reveal Selected", shortcut: "⇧⌘R")
                                ShortcutRow(action: "Previous / Next", shortcut: "⌘[ / ⌘]")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 560, minHeight: 520)
    }
}

struct ChronicleHelpView: View {
    @ObservedObject var model: ChronicleArchiveStore

    var body: some View {
        ZStack {
            ChronicleGlassBackdrop()

            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(alignment: .leading, spacing: 18) {
                        ChronicleGlassCard(title: "Chronicle REM") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Browse archived Chronicle frames, inspect the selected image, and jump straight to the raw archive when you need to work at file level.")
                                    .fixedSize(horizontal: false, vertical: true)

                                Button("Open Archive Folder") {
                                    model.openArchiveFolder()
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }

                        ChronicleGlassCard(title: "Keyboard Shortcuts") {
                            VStack(alignment: .leading, spacing: 6) {
                                ShortcutRow(action: "Find", shortcut: "⌘F")
                                ShortcutRow(action: "Reload", shortcut: "⌘R")
                                ShortcutRow(action: "Open Archive Folder", shortcut: "⌘O")
                                ShortcutRow(action: "Preferences", shortcut: "⌘,")
                                ShortcutRow(action: "Reveal Selected in Finder", shortcut: "⇧⌘R")
                                ShortcutRow(action: "Previous / Next", shortcut: "⌘[ / ⌘]")
                            }
                        }

                        ChronicleGlassCard(title: "Archive") {
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledContent("Folder") {
                                    Text(model.archiveFramesPath)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }

                                LabeledContent("Frames") {
                                    Text("\(model.allFrames.count)")
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 560, minHeight: 520)
    }
}

struct ChronicleAboutView: View {
    let version: String
    let build: String

    var body: some View {
        ZStack {
            ChronicleGlassBackdrop()

            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .center, spacing: 12) {
                            Image(nsImage: ChronicleAppIcon.make())
                                .resizable()
                                .scaledToFit()
                                .frame(width: 136, height: 136)
                                .shadow(color: .black.opacity(0.2), radius: 24, y: 10)

                            Text("Chronicle REM")
                                .font(.largeTitle.weight(.semibold))

                            Text("A native viewer for Chronicle archive frames.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        ChronicleGlassCard(title: "Build") {
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledContent("Version") {
                                    Text(version)
                                        .monospacedDigit()
                                }

                                LabeledContent("Build") {
                                    Text(build)
                                        .monospacedDigit()
                                }
                            }
                        }

                        ChronicleGlassCard(title: "What it does") {
                            Text("Browse the Chronicle archive, inspect frames, follow the file selection in Finder, and keep the archive surfaced in a regular Dock-visible macOS app.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}

private struct ShortcutRow: View {
    let action: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .foregroundStyle(.secondary)
                .monospaced()
        }
    }
}

final class ChronicleREMAppDelegate: NSObject, NSApplicationDelegate {
    private let store = ChronicleArchiveStore.shared
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var preferencesWindow: NSWindow!
    private var helpWindow: NSWindow!
    private var aboutWindow: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = ChronicleAppIcon.make()
        buildMainMenu()
        buildStatusItem()
        buildPreferencesWindow()
        buildHelpWindow()
        buildAboutWindow()
        buildWindow()
        store.reloadFrames()
        showWindow()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Chronicle REM")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Chronicle REM", action: #selector(showWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let openFolderItem = NSMenuItem(title: "Open Archive Folder", action: #selector(openArchiveFolder), keyEquivalent: "")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        let revealItem = NSMenuItem(title: "Reveal Selected in Finder", action: #selector(revealSelectedInFinder), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reloadFrames), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let playItem = NSMenuItem(title: "Play / Pause", action: #selector(togglePlayback), keyEquivalent: "p")
        playItem.target = self
        menu.addItem(playItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

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

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)

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

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")

        let openFolderItem = NSMenuItem(title: "Open Archive Folder", action: #selector(openArchiveFolder), keyEquivalent: "o")
        openFolderItem.target = self
        fileMenu.addItem(openFolderItem)

        let revealItem = NSMenuItem(title: "Reveal Selected in Finder", action: #selector(revealSelectedInFinder), keyEquivalent: "r")
        revealItem.target = self
        revealItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(revealItem)

        let openSelectedItem = NSMenuItem(title: "Open Selected", action: #selector(openSelectedInDefaultApp), keyEquivalent: "")
        openSelectedItem.target = self
        fileMenu.addItem(openSelectedItem)

        let copyPathItem = NSMenuItem(title: "Copy Selected Path", action: #selector(copySelectedPath), keyEquivalent: "c")
        copyPathItem.target = self
        copyPathItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(copyPathItem)

        let copyNameItem = NSMenuItem(title: "Copy Selected Name", action: #selector(copySelectedFilename), keyEquivalent: "")
        copyNameItem.target = self
        fileMenu.addItem(copyNameItem)

        fileMenu.addItem(NSMenuItem.separator())

        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reloadFrames), keyEquivalent: "r")
        reloadItem.target = self
        fileMenu.addItem(reloadItem)

        fileMenuItem.submenu = fileMenu

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")

        let previousItem = NSMenuItem(title: "Previous Frame", action: #selector(previousFrame), keyEquivalent: "[")
        previousItem.target = self
        previousItem.keyEquivalentModifierMask = .command
        viewMenu.addItem(previousItem)

        let nextItem = NSMenuItem(title: "Next Frame", action: #selector(nextFrame), keyEquivalent: "]")
        nextItem.target = self
        nextItem.keyEquivalentModifierMask = .command
        viewMenu.addItem(nextItem)

        let playPauseItem = NSMenuItem(title: "Play / Pause", action: #selector(togglePlayback), keyEquivalent: "")
        playPauseItem.target = self
        viewMenu.addItem(playPauseItem)

        viewMenuItem.submenu = viewMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")

        let findItem = NSMenuItem(title: "Find", action: #selector(focusSearchField), keyEquivalent: "f")
        findItem.target = self
        editMenu.addItem(findItem)

        editMenuItem.submenu = editMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")

        let minimizeItem = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(zoomItem)

        let closeItem = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(closeItem)

        windowMenu.addItem(NSMenuItem.separator())

        let bringAllItem = NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        bringAllItem.target = NSApp
        windowMenu.addItem(bringAllItem)

        windowMenuItem.submenu = windowMenu

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")

        let helpItem = NSMenuItem(title: "Chronicle REM Help", action: #selector(showHelp), keyEquivalent: "")
        helpItem.target = self
        helpMenu.addItem(helpItem)

        helpMenuItem.submenu = helpMenu
        NSApp.mainMenu = mainMenu
    }

    private func buildPreferencesWindow() {
        let rootView = ChroniclePreferencesView(model: store)
        let hostingController = NSHostingController(rootView: rootView)

        preferencesWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        preferencesWindow.contentViewController = hostingController
        styleGlassUtilityWindow(preferencesWindow, title: "Preferences", autosaveName: "Chronicle REM Preferences Glass")
    }

    private func buildHelpWindow() {
        let rootView = ChronicleHelpView(model: store)
        let hostingController = NSHostingController(rootView: rootView)

        helpWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        helpWindow.contentViewController = hostingController
        styleGlassUtilityWindow(helpWindow, title: "Help", autosaveName: "Chronicle REM Help Glass")
    }

    private func buildAboutWindow() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.7"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "7"
        let rootView = ChronicleAboutView(version: version, build: build)
        let hostingController = NSHostingController(rootView: rootView)

        aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        aboutWindow.contentViewController = hostingController
        styleGlassUtilityWindow(aboutWindow, title: "About Chronicle REM", autosaveName: "Chronicle REM About Glass")
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
        window.setFrameAutosaveName("Chronicle REM Main Window")
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()
        window.setFrame(NSRect(x: 120, y: 120, width: 1180, height: 760), display: false)
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func reloadFrames() {
        store.reloadFrames()
    }

    @objc private func previousFrame() {
        store.previousFrame()
    }

    @objc private func nextFrame() {
        store.nextFrame()
    }

    @objc private func togglePlayback() {
        store.togglePlayback()
    }

    @objc private func openArchiveFolder() {
        store.openArchiveFolder()
    }

    @objc private func revealSelectedInFinder() {
        store.revealSelectedInFinder()
    }

    @objc private func openSelectedInDefaultApp() {
        store.openSelectedInDefaultApp()
    }

    @objc private func copySelectedPath() {
        store.copySelectedPath()
    }

    @objc private func copySelectedFilename() {
        store.copySelectedFilename()
    }

    @objc private func showPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if preferencesWindow.isMiniaturized {
            preferencesWindow.deminiaturize(nil)
        }
        preferencesWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        if helpWindow.isMiniaturized {
            helpWindow.deminiaturize(nil)
        }
        helpWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func focusSearchField() {
        store.requestSearchFocus()
    }

    @objc private func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        if aboutWindow.isMiniaturized {
            aboutWindow.deminiaturize(nil)
        }
        aboutWindow.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ application: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func styleGlassUtilityWindow(_ window: NSWindow, title: String, autosaveName: String) {
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.center()
        window.setFrameAutosaveName(autosaveName)
    }
}

extension ChronicleREMAppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(revealSelectedInFinder),
             #selector(openSelectedInDefaultApp),
             #selector(copySelectedPath),
             #selector(copySelectedFilename):
            return store.selectedFrame != nil
        case #selector(previousFrame),
             #selector(nextFrame),
             #selector(togglePlayback):
            return !store.frames.isEmpty
        default:
            return true
        }
    }
}

let app = NSApplication.shared
let delegate = ChronicleREMAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
