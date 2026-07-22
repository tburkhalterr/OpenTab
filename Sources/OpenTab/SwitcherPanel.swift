// Sources/OpenTab/SwitcherPanel.swift
import Cocoa

final class SwitcherPanel: NSPanel {
    var onHover: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let cellStack = NSStackView()
    private let queryLabel = NSTextField(labelWithString: "")
    private var cells: [SwitcherCell] = []
    private var cellByID: [CGWindowID: SwitcherCell] = [:]
    private weak var selectedCell: SwitcherCell?
    private var windows: [WindowInfo] = []
    private var builtMetrics: CellMetrics?
    private var query = ""

    private static let thumbnailMaxSize: CGFloat = 320

    private static let outerInset: CGFloat = 16
    private static let queryHeight: CGFloat = 26
    private static let maxWidthFraction: CGFloat = 0.92
    private static let maxHeightFraction: CGFloat = 0.85

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 140),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .modalPanel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = makeContainer()
    }

    func present(windows: [WindowInfo], layout: SwitcherLayout, density: SwitcherDensity, thumbnails: Bool) {
        self.windows = windows
        let metrics = CellMetrics(layout: layout, density: density, thumbnails: thumbnails)

        cellStack.orientation = metrics.isList ? .vertical : .horizontal
        cellStack.spacing = metrics.stackSpacing
        cellStack.edgeInsets = NSEdgeInsets(top: metrics.stackInset, left: metrics.stackInset,
                                            bottom: metrics.stackInset, right: metrics.stackInset)
        // Cells are only re-created for the delta; metrics are fixed within a
        // session, so a change means a new session and forces a full rebuild.
        if builtMetrics == metrics {
            reconcileCells(windows, metrics: metrics)
        } else {
            rebuildCells(windows, metrics: metrics)
        }
        builtMetrics = metrics

        resizeToContent()
        orderFrontRegardless()
        if metrics.thumbnails { loadThumbnails(for: windows) }
    }

    private func rebuildCells(_ windows: [WindowInfo], metrics: CellMetrics) {
        cells.forEach { $0.removeFromSuperview() }
        cellByID.removeAll()
        cells = windows.enumerated().map { index, window in
            makeCell(window: window, metrics: metrics, index: index)
        }
        cells.forEach { cellStack.addArrangedSubview($0) }
    }

    // Reuse the existing cell for a window whose rendered content is unchanged;
    // build a fresh one only for new or mutated entries, then reorder in place.
    private func reconcileCells(_ windows: [WindowInfo], metrics: CellMetrics) {
        var next: [SwitcherCell] = []
        var nextByID: [CGWindowID: SwitcherCell] = [:]
        for (index, window) in windows.enumerated() {
            let reusable = cellByID[window.id].flatMap { $0.renders(window) ? $0 : nil }
            let cell = reusable ?? SwitcherCell(window: window, metrics: metrics)
            cell.onHover = { [weak self] in self?.onHover?(index) }
            cell.onSelect = { [weak self] in self?.onSelect?(index) }
            next.append(cell)
            nextByID[window.id] = cell
        }
        guard next != cells else { cellByID = nextByID; return }

        for stale in cells where nextByID[stale.windowInfo.id] !== stale { stale.removeFromSuperview() }
        for cell in next { cellStack.addArrangedSubview(cell) }
        cells = next
        cellByID = nextByID
    }

    private func makeCell(window: WindowInfo, metrics: CellMetrics, index: Int) -> SwitcherCell {
        let cell = SwitcherCell(window: window, metrics: metrics)
        cell.onHover = { [weak self] in self?.onHover?(index) }
        cell.onSelect = { [weak self] in self?.onSelect?(index) }
        cellByID[window.id] = cell
        return cell
    }

    // Only current-Space windows (those with an AX element) are capturable.
    private func loadThumbnails(for windows: [WindowInfo]) {
        let ids = windows.filter { $0.axElement != nil }.map(\.id)
        for id in ids {
            if let cached = ThumbnailProvider.cached(id) { cellByID[id]?.setThumbnail(cached) }
        }
        ThumbnailProvider.capture(ids, maxSize: Self.thumbnailMaxSize) { [weak self] id, image in
            self?.cellByID[id]?.setThumbnail(image)
        }
    }

    // Only the outgoing and incoming cells change state; at most one cell is ever
    // selected, so touching every cell (and reallocating its font) is wasteful.
    func highlight(index: Int) {
        let target = cells.indices.contains(index) ? cells[index] : nil
        if selectedCell !== target { selectedCell?.setSelected(false) }
        target?.setSelected(true)
        selectedCell = target
        guard let cell = target else { return }
        cell.scrollToVisible(cell.bounds.insetBy(dx: -60, dy: -60))
        cellStack.setAccessibilitySelectedChildren([cell])
        NSAccessibility.post(element: cell, notification: .selectedChildrenChanged)
    }

    func setQuery(_ text: String) {
        query = text
        resizeToContent()
    }

    override var canBecomeKey: Bool { false }

    private func makeContainer() -> NSView {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 20
        container.layer?.masksToBounds = true
        container.autoresizesSubviews = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = cellStack
        cellStack.translatesAutoresizingMaskIntoConstraints = true
        cellStack.setAccessibilityElement(true)
        cellStack.setAccessibilityRole(.list)
        cellStack.setAccessibilityLabel("Open windows")
        container.addSubview(scrollView)

        queryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        queryLabel.textColor = .labelColor
        queryLabel.alignment = .center
        queryLabel.lineBreakMode = .byTruncatingHead
        queryLabel.isHidden = true
        container.addSubview(queryLabel)
        return container
    }

    private func resizeToContent() {
        cellStack.layoutSubtreeIfNeeded()
        let content = cellStack.fittingSize
        cellStack.frame = NSRect(origin: .zero, size: content)

        let screen = ActiveScreen.current().visibleFrame
        let viewport = NSSize(width: min(content.width, screen.width * Self.maxWidthFraction),
                              height: min(content.height, screen.height * Self.maxHeightFraction))
        let inset = Self.outerInset
        let queryH = query.isEmpty ? 0 : Self.queryHeight
        let total = NSSize(width: viewport.width + inset * 2,
                           height: viewport.height + queryH + inset * 2)

        setContentSize(total)
        scrollView.frame = NSRect(x: inset, y: inset, width: viewport.width, height: viewport.height)
        queryLabel.isHidden = query.isEmpty
        queryLabel.stringValue = "🔍  " + query
        queryLabel.frame = NSRect(x: inset, y: inset + viewport.height, width: viewport.width, height: queryH)
        setFrameOrigin(NSPoint(x: screen.midX - total.width / 2, y: screen.midY - total.height / 2))
    }
}
