// Sources/OpenTab/SwitcherPanel.swift
import Cocoa

final class SwitcherPanel: NSPanel {
    private let cellStack = NSStackView()
    private var cells: [SwitcherCell] = []
    private var windows: [WindowInfo] = []

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

    func present(windows: [WindowInfo], layout: SwitcherLayout) {
        self.windows = windows
        cellStack.orientation = (layout == .list) ? .vertical : .horizontal
        cells.forEach { $0.removeFromSuperview() }
        cells = windows.map { SwitcherCell(window: $0, layout: layout) }
        cells.forEach { cellStack.addArrangedSubview($0) }

        layoutIfNeeded()
        sizeToFitActiveScreen()
        orderFrontRegardless()
    }

    func highlight(index: Int) {
        for (i, cell) in cells.enumerated() {
            cell.setSelected(i == index)
        }
    }

    override var canBecomeKey: Bool { false }

    private func makeContainer() -> NSView {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 20
        container.layer?.masksToBounds = true

        cellStack.spacing = 10
        cellStack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        cellStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cellStack)

        NSLayoutConstraint.activate([
            cellStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            cellStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            cellStack.topAnchor.constraint(equalTo: container.topAnchor),
            cellStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func sizeToFitActiveScreen() {
        let fitting = cellStack.fittingSize
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let width = min(fitting.width, screen.width - 40)
        let size = NSSize(width: width, height: fitting.height)
        setContentSize(size)
        setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
    }
}

private final class SwitcherCell: NSView {
    private let highlight = NSView()
    private let titleLabel: NSTextField

    init(window: WindowInfo, layout: SwitcherLayout) {
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

        let isList = layout == .list
        let iconView = makeIconView(window.icon)
        let textStack = makeTextStack(window: window, centered: !isList)

        let content = NSStackView(views: [iconView, textStack])
        content.orientation = isList ? .horizontal : .vertical
        content.alignment = isList ? .centerY : .centerX
        content.spacing = isList ? 12 : 8
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let iconSize: CGFloat = isList ? 32 : 60
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let width: CGFloat = isList ? 340 : 150
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func makeIconView(_ icon: NSImage?) -> NSImageView {
        let view = NSImageView()
        view.image = icon
        view.imageScaling = .scaleProportionallyUpOrDown
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func makeTextStack(window: WindowInfo, centered: Bool) -> NSStackView {
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = centered ? .center : .natural
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = centered ? 2 : 1

        let stack = NSStackView(views: [titleLabel])
        stack.orientation = .vertical
        stack.alignment = centered ? .centerX : .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

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
        field.alignment = .center
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
        titleLabel.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .medium)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
