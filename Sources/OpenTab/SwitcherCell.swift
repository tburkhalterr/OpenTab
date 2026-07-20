// Sources/OpenTab/SwitcherCell.swift
import Cocoa

struct CellMetrics: Equatable {
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

final class SwitcherCell: NSView {
    var onHover: (() -> Void)?
    var onSelect: (() -> Void)?

    let windowInfo: WindowInfo
    private let highlight = NSView()
    private let titleLabel: NSTextField
    private let metrics: CellMetrics
    private var applyThumbnail: ((NSImage) -> Void)?

    init(window: WindowInfo, metrics: CellMetrics) {
        self.windowInfo = window
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

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityDescription(for: window))
    }

    // "App, Window title, Minimized" — what VoiceOver announces for this entry.
    private func accessibilityDescription(for window: WindowInfo) -> String {
        var parts = [window.appName]
        if window.title != window.appName { parts.append(window.title) }
        if window.windowCount > 1 { parts.append("\(window.windowCount) windows") }
        if let state = stateText(for: window) { parts.append(state) }
        return parts.joined(separator: ", ")
    }

    func setThumbnail(_ image: NSImage) { applyThumbnail?(image) }

    // Whether this cell already renders `other` — i.e. every content-bearing
    // field it draws is unchanged, so the view can be reused as-is.
    func renders(_ other: WindowInfo) -> Bool {
        windowInfo.id == other.id &&
        windowInfo.title == other.title &&
        windowInfo.appName == other.appName &&
        windowInfo.windowCount == other.windowCount &&
        windowInfo.isMinimized == other.isMinimized &&
        windowInfo.isHidden == other.isHidden
    }

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
        setAccessibilitySelected(selected)
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
