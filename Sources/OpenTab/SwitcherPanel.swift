// Sources/OpenTab/SwitcherPanel.swift
import Cocoa

final class SwitcherPanel: NSPanel {
    private let scrollView = NSScrollView()
    private let cellStack = NSStackView()
    private var cells: [SwitcherCell] = []
    private var windows: [WindowInfo] = []

    private static let outerInset: CGFloat = 16
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = makeContainer()
    }

    func present(windows: [WindowInfo], layout: SwitcherLayout, density: SwitcherDensity) {
        self.windows = windows
        let metrics = CellMetrics(layout: layout, density: density)

        cellStack.orientation = (layout == .list) ? .vertical : .horizontal
        cellStack.spacing = metrics.stackSpacing
        cellStack.edgeInsets = NSEdgeInsets(top: metrics.stackInset, left: metrics.stackInset,
                                            bottom: metrics.stackInset, right: metrics.stackInset)
        cells.forEach { $0.removeFromSuperview() }
        cells = windows.map { SwitcherCell(window: $0, metrics: metrics) }
        cells.forEach { cellStack.addArrangedSubview($0) }

        resizeToContent()
        orderFrontRegardless()
    }

    func highlight(index: Int) {
        for (i, cell) in cells.enumerated() {
            cell.setSelected(i == index)
        }
        guard cells.indices.contains(index) else { return }
        let cell = cells[index]
        cell.scrollToVisible(cell.bounds.insetBy(dx: -60, dy: -60))
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
        return container
    }

    private func resizeToContent() {
        cellStack.layoutSubtreeIfNeeded()
        let content = cellStack.fittingSize
        cellStack.frame = NSRect(origin: .zero, size: content)

        let screen = activeScreen().visibleFrame
        let viewport = NSSize(width: min(content.width, screen.width * Self.maxWidthFraction),
                              height: min(content.height, screen.height * Self.maxHeightFraction))
        let inset = Self.outerInset
        let total = NSSize(width: viewport.width + inset * 2, height: viewport.height + inset * 2)

        setContentSize(total)
        scrollView.frame = NSRect(x: inset, y: inset, width: viewport.width, height: viewport.height)
        setFrameOrigin(NSPoint(x: screen.midX - total.width / 2, y: screen.midY - total.height / 2))
    }

    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private struct CellMetrics {
    let isList: Bool
    let iconSize: CGFloat
    let cellWidth: CGFloat
    let titleSize: CGFloat
    let titleLines: Int
    let showSecondary: Bool
    let contentPadding: CGFloat
    let contentSpacing: CGFloat
    let stackSpacing: CGFloat
    let stackInset: CGFloat

    init(layout: SwitcherLayout, density: SwitcherDensity) {
        isList = layout == .list
        let compact = density == .compact
        showSecondary = !compact
        titleLines = (isList || compact) ? 1 : 2
        stackSpacing = compact ? 6 : 10
        stackInset = compact ? 12 : 18
        contentPadding = compact ? 6 : 10
        titleSize = compact ? 11 : 12

        switch (isList, compact) {
        case (true, false):  iconSize = 32; cellWidth = 340; contentSpacing = 12
        case (true, true):   iconSize = 20; cellWidth = 260; contentSpacing = 9
        case (false, false): iconSize = 60; cellWidth = 150; contentSpacing = 8
        case (false, true):  iconSize = 34; cellWidth = 104; contentSpacing = 6
        }
    }
}

private final class SwitcherCell: NSView {
    private let highlight = NSView()
    private let titleLabel: NSTextField
    private let metrics: CellMetrics

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

        let iconView = makeIconView(window.icon)
        let textStack = makeTextStack(window: window)

        let content = NSStackView(views: [iconView, textStack])
        content.orientation = metrics.isList ? .horizontal : .vertical
        content.alignment = metrics.isList ? .centerY : .centerX
        content.spacing = metrics.contentSpacing
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let pad = metrics.contentPadding
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: metrics.iconSize),
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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
