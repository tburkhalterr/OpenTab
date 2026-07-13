// Sources/OpenTab/SwitcherPanel.swift
import Cocoa

/// A borderless, non-activating panel that draws the window entries.
/// The layout is a horizontal row of icon+title cells (the `.appGrid` mode);
/// `.list` and `.appOnly` reuse the same cells with different stacking.
final class SwitcherPanel: NSPanel {
    private let stack = NSStackView()
    private var cells: [SwitcherCell] = []

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

        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true

        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        contentView = container
    }

    func present(windows: [WindowInfo], layout: SwitcherLayout) {
        stack.orientation = (layout == .list) ? .vertical : .horizontal
        cells.forEach { $0.removeFromSuperview() }
        cells = windows.map { SwitcherCell(window: $0, layout: layout) }
        cells.forEach { stack.addArrangedSubview($0) }

        layoutIfNeeded()
        centerOnActiveScreen()
        orderFrontRegardless()
    }

    func highlight(index: Int) {
        for (i, cell) in cells.enumerated() {
            cell.setSelected(i == index)
        }
    }

    private func centerOnActiveScreen() {
        guard let screen = NSScreen.main else { return }
        let size = stack.fittingSize
        setContentSize(size)
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        setFrameOrigin(origin)
    }

    override var canBecomeKey: Bool { false }
}

/// One entry: application icon plus a truncated title.
private final class SwitcherCell: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let highlight = NSView()

    init(window: WindowInfo, layout: SwitcherLayout) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 10
        highlight.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        highlight.isHidden = true
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        iconView.image = window.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = window.title
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [iconView, titleLabel])
        content.orientation = (layout == .list) ? .horizontal : .vertical
        content.alignment = (layout == .list) ? .centerY : .centerX
        content.spacing = (layout == .list) ? 10 : 6
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let iconSize: CGFloat = (layout == .list) ? 28 : 56
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let width = (layout == .list) ? CGFloat(260) : CGFloat(96)
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    func setSelected(_ selected: Bool) {
        highlight.isHidden = !selected
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
