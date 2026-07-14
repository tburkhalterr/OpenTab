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
    private var windows: [WindowInfo] = []
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

        cellStack.orientation = (layout == .list) ? .vertical : .horizontal
        cellStack.spacing = metrics.stackSpacing
        cellStack.edgeInsets = NSEdgeInsets(top: metrics.stackInset, left: metrics.stackInset,
                                            bottom: metrics.stackInset, right: metrics.stackInset)
        cells.forEach { $0.removeFromSuperview() }
        cellByID.removeAll()
        cells = windows.enumerated().map { index, window in
            let cell = SwitcherCell(window: window, metrics: metrics)
            cell.onHover = { [weak self] in self?.onHover?(index) }
            cell.onSelect = { [weak self] in self?.onSelect?(index) }
            cellByID[window.id] = cell
            return cell
        }
        cells.forEach { cellStack.addArrangedSubview($0) }

        resizeToContent()
        orderFrontRegardless()
        if metrics.thumbnails { loadThumbnails(for: windows) }
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

    func highlight(index: Int) {
        for (i, cell) in cells.enumerated() {
            cell.setSelected(i == index)
        }
        guard cells.indices.contains(index) else { return }
        let cell = cells[index]
        cell.scrollToVisible(cell.bounds.insetBy(dx: -60, dy: -60))
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

private struct CellMetrics {
    let isList: Bool
    let thumbnails: Bool
    let iconSize: CGFloat
    let mediaSize: CGSize
    let cellWidth: CGFloat
    let titleSize: CGFloat
    let titleLines: Int
    let showSecondary: Bool
    let contentPadding: CGFloat
    let contentSpacing: CGFloat
    let stackSpacing: CGFloat
    let stackInset: CGFloat

    init(layout: SwitcherLayout, density: SwitcherDensity, thumbnails: Bool) {
        isList = layout == .list
        let compact = density == .compact
        // Thumbnails only make sense in the roomy grid layout.
        self.thumbnails = thumbnails && !isList && !compact
        showSecondary = !compact
        titleLines = (isList || compact) ? 1 : 2
        stackSpacing = compact ? 6 : 10
        stackInset = compact ? 12 : 18
        contentPadding = compact ? 6 : 10
        titleSize = compact ? 11 : 12

        let baseWidth: CGFloat
        switch (isList, compact) {
        case (true, false):  iconSize = 32; baseWidth = 340; contentSpacing = 12
        case (true, true):   iconSize = 20; baseWidth = 260; contentSpacing = 9
        case (false, false): iconSize = 60; baseWidth = 150; contentSpacing = 8
        case (false, true):  iconSize = 34; baseWidth = 104; contentSpacing = 6
        }

        if self.thumbnails {
            mediaSize = CGSize(width: 168, height: 104)
            cellWidth = 188
        } else {
            mediaSize = CGSize(width: iconSize, height: iconSize)
            cellWidth = baseWidth
        }
    }
}

private final class SwitcherCell: NSView {
    var onHover: (() -> Void)?
    var onSelect: (() -> Void)?

    private let highlight = NSView()
    private let titleLabel: NSTextField
    private let metrics: CellMetrics
    private var applyThumbnail: ((NSImage) -> Void)?

    init(window: WindowInfo, metrics: CellMetrics) {
        self.metrics = metrics
        self.titleLabel = NSTextField(labelWithString: window.title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 12
        highlight.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        highlight.isHidden = true
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        let media = makeMedia(window: window)
        let textStack = makeTextStack(window: window)

        let content = NSStackView(views: [media, textStack])
        content.orientation = metrics.isList ? .horizontal : .vertical
        content.alignment = metrics.isList ? .centerY : .centerX
        content.spacing = metrics.contentSpacing
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let pad = metrics.contentPadding
        NSLayoutConstraint.activate([
            media.widthAnchor.constraint(equalToConstant: metrics.mediaSize.width),
            media.heightAnchor.constraint(equalToConstant: metrics.mediaSize.height),
            content.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad + 2),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(pad + 2)),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        widthAnchor.constraint(equalToConstant: metrics.cellWidth).isActive = true
    }

    func setThumbnail(_ image: NSImage) { applyThumbnail?(image) }

    private func makeMedia(window: WindowInfo) -> NSView {
        guard metrics.thumbnails else { return makeIconView(window.icon) }

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.masksToBounds = true
        box.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.5).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let icon = makeIconView(window.icon)          // fallback until the shot loads
        let thumb = makeIconView(nil); thumb.isHidden = true
        let badge = makeIconView(window.icon); badge.isHidden = true
        box.addSubview(thumb); box.addSubview(icon); box.addSubview(badge)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            thumb.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            thumb.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            thumb.topAnchor.constraint(equalTo: box.topAnchor),
            thumb.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            badge.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
            badge.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22)
        ])

        applyThumbnail = { image in
            thumb.image = image
            thumb.isHidden = false
            icon.isHidden = true
            badge.isHidden = false
        }
        return box
    }

    private func makeIconView(_ icon: NSImage?) -> NSImageView {
        let view = NSImageView()
        view.image = icon
        view.imageScaling = .scaleProportionallyUpOrDown
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func makeTextStack(window: WindowInfo) -> NSStackView {
        titleLabel.font = .systemFont(ofSize: metrics.titleSize, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = metrics.isList ? .natural : .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = metrics.titleLines

        let stack = NSStackView(views: [titleLabel])
        stack.orientation = .vertical
        stack.alignment = metrics.isList ? .leading : .centerX
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard metrics.showSecondary else { return stack }

        if window.appName != window.title {
            stack.addArrangedSubview(label(window.appName, size: 10, color: .secondaryLabelColor))
        }
        if window.windowCount > 1 {
            stack.addArrangedSubview(label("\(window.windowCount) windows", size: 9, color: .tertiaryLabelColor))
        }
        if let state = stateText(for: window) {
            stack.addArrangedSubview(label(state, size: 9, color: .systemOrange))
        }
        return stack
    }

    private func label(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        field.alignment = metrics.isList ? .natural : .center
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        return field
    }

    private func stateText(for window: WindowInfo) -> String? {
        if window.isMinimized { return "Minimized" }
        if window.isHidden { return "Hidden" }
        return nil
    }

    func setSelected(_ selected: Bool) {
        highlight.isHidden = !selected
        titleLabel.font = .systemFont(ofSize: metrics.titleSize, weight: selected ? .semibold : .medium)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseUp(with event: NSEvent) { onSelect?() }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
