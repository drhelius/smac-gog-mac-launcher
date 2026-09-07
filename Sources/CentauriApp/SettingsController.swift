import AppKit
import CentauriCore

final class SettingsController: NSObject
{
    private var window: NSWindow!
    private var options: PlayOptions
    private var save: (PlayOptions) throws -> Void
    private var wine: () -> Void
    private var fields: [String: NSTextField] = [:]
    private var checks: [String: NSButton] = [:]
    private var sliders: [String: NSSlider] = [:]
    private var values: [String: NSTextField] = [:]
    private let animation = NSPopUpButton()
    private let display = NSPopUpButton()

    init(options: PlayOptions, save: @escaping (PlayOptions) throws -> Void, wine: @escaping () -> Void)
    {
        self.options = options
        self.save = save
        self.wine = wine
    }

    func show(on parent: NSWindow, installed: Bool)
    {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 670, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.heightAnchor.constraint(equalToConstant: 360).isActive = true
        display.addItems(withTitles: ["Fullscreen", "Window"])
        display.target = self
        display.action = #selector(displayChanged)
        addTab("Display", to: tabs, rows: [
            [Interface.label("Display mode"), display],
            [Interface.label("Window size"), Interface.stack([number("width"), Interface.label("×", color: .secondaryLabelColor), number("height")], vertical: false)],
            [Interface.label("Interface font"), number("mainFontSize", suffix: "pt")],
            [Interface.label("Interlude font"), number("interludeFontSize", suffix: "pt")],
            [Interface.label("Gamma"), slider("gamma", max: 200, min: 50, percent: false)],
            [Interface.label("Movies"), checkbox("moviesEnabled", "Play cutscenes")],
            [NSView(), checkbox("showIntro", "Show opening movie")]
        ])
        addTab("Audio", to: tabs, rows: [
            [Interface.label("Master"), slider("masterVolume", max: 127)],
            [Interface.label("Music"), slider("musicVolume", max: 127)],
            [Interface.label("Effects"), slider("effectsVolume", max: 127)],
            [Interface.label("Speech"), slider("voiceVolume", max: 127)],
            [Interface.label("Movies"), slider("movieVolume", max: 100)]
        ])
        animation.addItems(withTitles: ["Standard", "Fast", "Smooth"])
        addTab("Gameplay", to: tabs, rows: [
            [Interface.label("Unit animation"), animation],
            [Interface.label("Preferences"), checkbox("preserveBeginnerPreferences", "Keep preferences in beginner games")],
            [Interface.label("File dialogs"), checkbox("systemFileDialogs", "Use Windows file dialogs")]
        ])
        let renderer = checkbox("legacyVoxel", "Use legacy voxel renderer")
        renderer.toolTip = "Uses the legacy voxel-rendering algorithm. Disabled by default."
        let switching = checkbox("directDraw", "Allow display resolution switching")
        switching.toolTip = "Lets the game's DirectDraw code change display resolution. Disabled by default."
        let spatial = checkbox("positionalAudio", "Enable 3D positional audio")
        spatial.toolTip = "Enables the game's hardware positional-audio path. Disabled by default."
        let eax = checkbox("eaxAudio", "Enable EAX effects")
        eax.toolTip = "Enables the game's EAX sound effects. Disabled by default."
        let wineButton = Interface.button("Wine Settings…", symbol: "gearshape", target: self, action: #selector(configureWine))
        wineButton.isEnabled = installed
        addTab("Compatibility", to: tabs, rows: [
            [Interface.label("Rendering"), renderer],
            [NSView(), switching],
            [Interface.label("Audio"), spatial],
            [NSView(), eax],
            [Interface.label("Runtime"), wineButton]
        ])
        let reset = Interface.button("Reset Defaults", target: self, action: #selector(resetDefaults))
        let cancel = Interface.button("Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let done = Interface.button("Save", target: self, action: #selector(apply))
        done.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = Interface.stack([reset, spacer, cancel, done], vertical: false)
        let content = Interface.stack([tabs, footer], spacing: 20)
        Interface.inset(content, in: window.contentView!, amount: 24)
        tabs.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        footer.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        loadFields()
        parent.beginSheet(window)
    }

    private func addTab(_ title: String, to tabs: NSTabView, rows: [[NSView]])
    {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let view = NSView()
        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 18
        grid.columnSpacing = 24
        grid.xPlacement = .leading
        grid.yPlacement = .center
        grid.column(at: 0).width = 135
        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        item.view = view
        tabs.addTabViewItem(item)
    }

    private func number(_ key: String, suffix: String? = nil) -> NSView
    {
        let field = NSTextField()
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = false
        field.formatter = formatter
        field.setAccessibilityLabel(["width": "Window width", "height": "Window height", "mainFontSize": "Interface font size", "interludeFontSize": "Interlude font size"][key] ?? key)
        fields[key] = field
        if let suffix = suffix { return Interface.stack([field, Interface.label(suffix, color: .secondaryLabelColor)], vertical: false, spacing: 6) }
        return field
    }

    private func checkbox(_ key: String, _ label: String) -> NSButton
    {
        let button = NSButton(checkboxWithTitle: label, target: self, action: #selector(checkChanged))
        checks[key] = button
        return button
    }

    private func slider(_ key: String, max: Double, min: Double = 0, percent: Bool = true) -> NSView
    {
        let slider = NSSlider(value: max, minValue: min, maxValue: max, target: self, action: #selector(sliderChanged(_:)))
        slider.identifier = NSUserInterfaceItemIdentifier(key)
        slider.setAccessibilityLabel(["masterVolume": "Master volume", "musicVolume": "Music volume", "effectsVolume": "Effects volume", "voiceVolume": "Speech volume", "movieVolume": "Movie volume", "gamma": "Gamma"][key] ?? key)
        slider.widthAnchor.constraint(equalToConstant: 265).isActive = true
        slider.isContinuous = true
        slider.toolTip = percent ? "Volume" : "100 is the default gamma"
        let label = Interface.label("", size: 12, color: .secondaryLabelColor)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 42).isActive = true
        sliders[key] = slider
        values[key] = label
        return Interface.stack([slider, label], vertical: false)
    }

    @objc private func sliderChanged(_ slider: NSSlider)
    {
        guard let key = slider.identifier?.rawValue else { return }
        let number = key == "gamma" ? slider.integerValue : Int((slider.doubleValue / slider.maxValue * 100).rounded())
        values[key]?.stringValue = key == "gamma" ? "\(number)" : "\(number)%"
    }

    @objc private func displayChanged()
    {
        fields["width"]?.isEnabled = display.indexOfSelectedItem == 1
        fields["height"]?.isEnabled = display.indexOfSelectedItem == 1
    }

    @objc private func checkChanged()
    {
        checks["showIntro"]?.isEnabled = checks["moviesEnabled"]?.state == .on
    }

    private func loadFields()
    {
        display.selectItem(at: options.windowed ? 1 : 0)
        animation.selectItem(at: UnitAnimation.allCases.firstIndex(of: options.animation) ?? 0)
        for (key, value) in ["width": options.width, "height": options.height, "mainFontSize": options.mainFontSize, "interludeFontSize": options.interludeFontSize]
        {
            fields[key]?.integerValue = value
        }
        let flags = ["moviesEnabled": options.moviesEnabled, "showIntro": !options.skipIntro, "legacyVoxel": options.legacyVoxel,
                     "directDraw": options.directDraw, "positionalAudio": options.positionalAudio, "eaxAudio": options.eaxAudio,
                     "systemFileDialogs": options.systemFileDialogs, "preserveBeginnerPreferences": options.preserveBeginnerPreferences]
        for (key, value) in flags { checks[key]?.state = value ? .on : .off }
        let volumes = ["masterVolume": options.masterVolume, "musicVolume": options.musicVolume, "effectsVolume": options.effectsVolume,
                       "voiceVolume": options.voiceVolume, "movieVolume": options.movieVolume, "gamma": options.gamma]
        for (key, value) in volumes
        {
            sliders[key]?.integerValue = value
            if let slider = sliders[key] { sliderChanged(slider) }
        }
        displayChanged()
        checkChanged()
    }

    @objc private func resetDefaults() { options = PlayOptions(); loadFields() }

    @objc private func apply()
    {
        window.makeFirstResponder(nil)
        options.windowed = display.indexOfSelectedItem == 1
        options.width = fields["width"]!.integerValue
        options.height = fields["height"]!.integerValue
        options.mainFontSize = fields["mainFontSize"]!.integerValue
        options.interludeFontSize = fields["interludeFontSize"]!.integerValue
        options.animation = UnitAnimation.allCases[max(0, animation.indexOfSelectedItem)]
        options.skipIntro = checks["showIntro"]!.state != .on
        options.moviesEnabled = checks["moviesEnabled"]!.state == .on
        options.legacyVoxel = checks["legacyVoxel"]!.state == .on
        options.directDraw = checks["directDraw"]!.state == .on
        options.positionalAudio = checks["positionalAudio"]!.state == .on
        options.eaxAudio = checks["eaxAudio"]!.state == .on
        options.systemFileDialogs = checks["systemFileDialogs"]!.state == .on
        options.preserveBeginnerPreferences = checks["preserveBeginnerPreferences"]!.state == .on
        options.masterVolume = sliders["masterVolume"]!.integerValue
        options.musicVolume = sliders["musicVolume"]!.integerValue
        options.effectsVolume = sliders["effectsVolume"]!.integerValue
        options.voiceVolume = sliders["voiceVolume"]!.integerValue
        options.movieVolume = sliders["movieVolume"]!.integerValue
        options.gamma = sliders["gamma"]!.integerValue
        do { try save(options); cancel() }
        catch { NSAlert(error: error).runModal() }
    }

    @objc private func cancel() { window.sheetParent?.endSheet(window); window.orderOut(nil) }
    @objc private func configureWine() { cancel(); wine() }
}
