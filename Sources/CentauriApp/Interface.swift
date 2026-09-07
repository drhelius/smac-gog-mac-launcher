import AppKit
import CentauriCore

enum Interface
{
    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField
    {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    static func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 12) -> NSStackView
    {
        let stack = NSStackView(views: views)
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        stack.spacing = spacing
        return stack
    }

    static func button(_ title: String, symbol: String? = nil, target: AnyObject?, action: Selector) -> NSButton
    {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        if let symbol = symbol
        {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
        }
        return button
    }

    static func inset(_ content: NSView, in parent: NSView, amount: CGFloat = 20)
    {
        content.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: amount),
            content.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -amount),
            content.topAnchor.constraint(equalTo: parent.topAnchor, constant: amount),
            content.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -amount)
        ])
    }

    static func card(_ content: NSView, inset: CGFloat = 18) -> NSView
    {
        let view = NSBox()
        view.boxType = .custom
        view.borderWidth = 1
        view.borderColor = .separatorColor
        view.fillColor = .controlBackgroundColor
        view.cornerRadius = 10
        view.contentViewMargins = .zero
        self.inset(content, in: view.contentView!, amount: inset)
        return view
    }

    static var icon: NSImage?
    {
        guard let resources = Bundle.main.resourceURL else { return nil }
        return NSImage(contentsOf: resources.appendingPathComponent("AppIcon.png"))
    }
}

final class CanvasView: NSView
{
    override func draw(_ dirtyRect: NSRect)
    {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

final class GameButton: NSButton
{
    let game: Game
    override var isFlipped: Bool { false }

    init(game: Game, target: AnyObject, action: Selector)
    {
        self.game = game
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = game.title
        isBordered = false
        setButtonType(.pushOnPushOff)
        setAccessibilityLabel(game.title)
        heightAnchor.constraint(equalToConstant: 66).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect)
    {
        if state == .on || isHighlighted
        {
            NSColor.controlAccentColor.withAlphaComponent(state == .on ? 0.16 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
        }
        let symbol = game == .alphaCentauri ? "globe.europe.africa.fill" : "sparkles"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 23, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [state == .on ? .controlAccentColor : .secondaryLabelColor]))
        image?.draw(in: NSRect(x: 14, y: (bounds.height - 28) / 2, width: 28, height: 28))
        let color = state == .on ? NSColor.controlAccentColor : .labelColor
        let name = game == .alphaCentauri ? "Alpha Centauri" : "Alien Crossfire"
        (name as NSString).draw(at: NSPoint(x: 54, y: 33), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color])
        let detail = game == .alphaCentauri ? "Original game" : "Expansion"
        (detail as NSString).draw(at: NSPoint(x: 54, y: 16), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
    }
}

final class GameHero: NSView
{
    private let heading = Interface.label("SID MEIER’S", size: 10, weight: .semibold, color: NSColor.white.withAlphaComponent(0.62))
    private let name = Interface.label("Alpha Centauri", size: 32, weight: .semibold, color: .white)
    private let detail = Interface.label("Planetary Pack", size: 13, color: NSColor.white.withAlphaComponent(0.7))
    private let icon = NSImageView()
    private var game: Game = .alphaCentauri

    override init(frame: NSRect)
    {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        let text = Interface.stack([heading, name, detail], spacing: 10)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        icon.image = Interface.icon
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 26
        icon.layer?.masksToBounds = true
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: icon.leadingAnchor, constant: -12),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 142),
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor),
            heightAnchor.constraint(equalToConstant: 210)
        ])
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func select(_ game: Game)
    {
        self.game = game
        heading.stringValue = game == .alphaCentauri ? "SID MEIER’S" : "ALPHA CENTAURI"
        name.stringValue = game.title
        detail.stringValue = game == .alphaCentauri ? "Planetary Pack" : "Alien Crossfire expansion"
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect)
    {
        let end = game == .alphaCentauri
            ? NSColor(calibratedRed: 0.08, green: 0.27, blue: 0.30, alpha: 1)
            : NSColor(calibratedRed: 0.19, green: 0.16, blue: 0.34, alpha: 1)
        NSGradient(starting: NSColor(calibratedRed: 0.055, green: 0.085, blue: 0.14, alpha: 1), ending: end)?.draw(in: bounds, angle: 0)
    }
}
