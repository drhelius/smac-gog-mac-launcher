import AppKit
import CentauriCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate
{
    private let service: CentauriService =
    {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1)
        {
            return CentauriService(layout: Layout(root: URL(fileURLWithPath: args[index + 1], isDirectory: true)))
        }
        return CentauriService()
    }()
    private var window: NSWindow!
    private var settingsController: SettingsController?
    private var options = PlayOptions()
    private var selectedGame: Game = .alphaCentauri
    private var gameButtons: [GameButton] = []
    private let hero = GameHero(frame: .zero)
    private let status = Interface.label("", size: 12, color: .secondaryLabelColor)
    private let progress = NSProgressIndicator()
    private let sourceField = Interface.label("", size: 12, color: .secondaryLabelColor)
    private let primary = NSButton()
    private let stopButton = NSButton()
    private let sourceButton = NSButton()
    private let saveImportButton = NSButton()
    private let settingsButton = NSButton()
    private let display = NSSegmentedControl(labels: ["Fullscreen", "Window"], trackingMode: .selectOne, target: nil, action: nil)
    private let resolution = NSPopUpButton()
    private let openingMovie = NSSwitch()
    private var setupCard: NSView!
    private var displayGrid: NSGridView!
    private var source: URL?
    private var saves: URL?
    private var token: Cancellation?
    private var playing = false
    private var quitWhenFinished = false

    func applicationDidFinishLaunching(_ notification: Notification)
    {
        options = service.options()
        let index = UserDefaults.standard.integer(forKey: "selectedGame")
        selectedGame = Game.allCases.indices.contains(index) ? Game.allCases[index] : .alphaCentauri
        let candidate = URL(fileURLWithPath: "/Applications/Sid Meier's Alpha Centauri Planetary Pack.app")
        if FileManager.default.fileExists(atPath: candidate.path) { source = candidate }
        createMenu()
        createWindow()
        refresh()
        status.stringValue = service.manifest == nil ? "Select game files to install" : "Ready"
        if let index = CommandLine.arguments.firstIndex(of: "--render-ui"), CommandLine.arguments.indices.contains(index + 1)
        {
            DispatchQueue.main.async
            {
                self.window.contentView?.layoutSubtreeIfNeeded()
                self.render(self.window.contentView!, to: CommandLine.arguments[index + 1])
                if let settingsIndex = CommandLine.arguments.firstIndex(of: "--render-settings"), CommandLine.arguments.indices.contains(settingsIndex + 1)
                {
                    self.showSettings()
                    self.settingsController?.render(to: CommandLine.arguments[settingsIndex + 1])
                }
                exit(0)
            }
        }
        else
        {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func render(_ view: NSView, to path: String)
    {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func createMenu()
    {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "About SMAC Launcher", action: #selector(about), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit SMAC Launcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        menu.addItem(appItem)
        let fileItem = NSMenuItem()
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open Saved Games", action: #selector(openSaves), keyEquivalent: "")
        file.addItem(withTitle: "Open Game Files", action: #selector(openGameFiles), keyEquivalent: "")
        file.addItem(withTitle: "Open Configuration", action: #selector(openConfiguration), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Export Diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: "")
        fileItem.submenu = file
        menu.addItem(fileItem)
        let helpItem = NSMenuItem()
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "SMAC Launcher on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        help.addItem(withTitle: "GOG Planetary Pack", action: #selector(openGOG), keyEquivalent: "")
        help.addItem(.separator())
        help.addItem(withTitle: "Install Rosetta…", action: #selector(installRosetta), keyEquivalent: "")
        helpItem.submenu = help
        menu.addItem(helpItem)
        NSApp.mainMenu = menu
    }

    private func createWindow()
    {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "SMAC Launcher"
        window.contentMinSize = NSSize(width: 900, height: 640)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let root = window.contentView!
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 230)
        ])
        let brandIcon = NSImageView()
        brandIcon.image = Interface.icon
        brandIcon.imageScaling = .scaleProportionallyUpOrDown
        brandIcon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        brandIcon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let brandText = Interface.stack([Interface.label("SMAC Launcher", size: 16, weight: .semibold), Interface.label("DrHelius", size: 11, color: .secondaryLabelColor)], spacing: 3)
        let brand = Interface.stack([brandIcon, brandText], vertical: false, spacing: 10)
        let gamesTitle = Interface.label("GAMES", size: 10, weight: .semibold, color: .secondaryLabelColor)
        let navigation = Interface.stack([brand, NSView(), gamesTitle], spacing: 14)
        for game in Game.allCases
        {
            let button = GameButton(game: game, target: self, action: #selector(selectGame(_:)))
            gameButtons.append(button)
            navigation.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 198).isActive = true
        }
        navigation.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(navigation)
        NSLayoutConstraint.activate([
            navigation.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 28),
            navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16)
        ])
        settingsButton.title = "Settings"
        settingsButton.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        settingsButton.imagePosition = .imageLeading
        settingsButton.bezelStyle = .rounded
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)
        let saved = Interface.button("Saved Games", symbol: "folder", target: self, action: #selector(openSaves))
        let files = Interface.button("Game Files", symbol: "folder.badge.gearshape", target: self, action: #selector(openGameFiles))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let bottom = Interface.stack([saved, files, settingsButton, Interface.label(version, size: 10, color: .tertiaryLabelColor)], spacing: 12)
        bottom.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(bottom)
        NSLayoutConstraint.activate([
            bottom.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 24),
            bottom.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -24)
        ])

        let main = CanvasView()
        main.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(main)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), main.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            main.topAnchor.constraint(equalTo: root.topAnchor), main.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        sourceField.lineBreakMode = .byTruncatingMiddle
        sourceButton.title = "Choose…"
        sourceButton.bezelStyle = .rounded
        sourceButton.target = self
        sourceButton.action = #selector(chooseSource)
        saveImportButton.title = "Import Saves…"
        saveImportButton.bezelStyle = .rounded
        saveImportButton.target = self
        saveImportButton.action = #selector(chooseSaves)
        setupCard = Interface.card(Interface.stack([
            Interface.label("Game Files", size: 13, weight: .semibold),
            Interface.stack([sourceField, sourceButton, saveImportButton], vertical: false)
        ]))
        display.target = self
        display.setAccessibilityLabel("Display mode")
        display.action = #selector(changeDisplay)
        display.widthAnchor.constraint(equalToConstant: 225).isActive = true
        for size in ["1024 × 768", "1280 × 800", "1600 × 900", "1920 × 1080", "Custom…"] { resolution.addItem(withTitle: size) }
        resolution.target = self
        resolution.setAccessibilityLabel("Window size")
        resolution.action = #selector(changeResolution)
        openingMovie.target = self
        openingMovie.setAccessibilityLabel("Opening movie")
        openingMovie.action = #selector(changeOpeningMovie)
        displayGrid = NSGridView(views: [
            [Interface.label("Display"), display],
            [Interface.label("Window size"), resolution],
            [Interface.label("Opening movie"), openingMovie]
        ])
        displayGrid.column(at: 0).width = 180
        displayGrid.columnSpacing = 20
        displayGrid.rowSpacing = 16
        displayGrid.xPlacement = .leading
        displayGrid.yPlacement = .center
        let settingsCard = Interface.card(displayGrid)
        primary.bezelStyle = .rounded
        primary.controlSize = .large
        primary.bezelColor = .controlAccentColor
        primary.font = .systemFont(ofSize: 15, weight: .semibold)
        primary.keyEquivalent = "\r"
        primary.target = self
        primary.action = #selector(primaryAction)
        primary.widthAnchor.constraint(equalToConstant: 160).isActive = true
        primary.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stopButton.title = "Stop"
        stopButton.bezelStyle = .rounded
        stopButton.target = self
        stopButton.action = #selector(stop)
        let advanced = Interface.button("Advanced Settings…", target: self, action: #selector(showSettings))
        let actions = Interface.stack([primary, stopButton, advanced], vertical: false, spacing: 14)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        let feedback = Interface.stack([progress, status], vertical: false, spacing: 8)
        let content = Interface.stack([hero, setupCard, settingsCard, actions, feedback], spacing: 22)
        content.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: main.topAnchor, constant: 28),
            content.bottomAnchor.constraint(lessThanOrEqualTo: main.bottomAnchor, constant: -24)
        ])
        for view in [hero, setupCard!, settingsCard] { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
    }

    private func refresh()
    {
        let installed = service.manifest != nil
        let busy = token != nil
        hero.select(selectedGame)
        for button in gameButtons
        {
            button.state = button.game == selectedGame ? .on : .off
            button.isEnabled = !busy
            button.needsDisplay = true
        }
        setupCard.isHidden = installed
        sourceField.stringValue = source?.lastPathComponent ?? "GOG application, game folder or installer"
        primary.title = installed ? "Play" : "Install"
        primary.isEnabled = !busy && (installed || source != nil)
        stopButton.isHidden = !busy
        stopButton.title = playing ? "Stop Game" : "Cancel"
        sourceButton.isEnabled = !busy
        saveImportButton.isEnabled = !busy
        settingsButton.isEnabled = !busy
        display.isEnabled = !busy
        resolution.isEnabled = !busy
        openingMovie.isEnabled = !busy && options.moviesEnabled
        display.selectedSegment = options.windowed ? 1 : 0
        displayGrid.row(at: 1).isHidden = !options.windowed
        openingMovie.state = options.skipIntro ? .off : .on
        let size = "\(options.width) × \(options.height)"
        if resolution.itemTitles.contains(size) { resolution.selectItem(withTitle: size) }
        else { resolution.selectItem(withTitle: "Custom…") }
    }

    @objc private func selectGame(_ button: GameButton)
    {
        selectedGame = button.game
        UserDefaults.standard.set(Game.allCases.firstIndex(of: selectedGame) ?? 0, forKey: "selectedGame")
        refresh()
    }

    private func saveSettings()
    {
        do { try service.saveOptions(options) }
        catch { options = service.options(); showError(error) }
        refresh()
    }

    @objc private func changeDisplay() { options.windowed = display.selectedSegment == 1; saveSettings() }
    @objc private func changeOpeningMovie() { options.skipIntro = openingMovie.state != .on; saveSettings() }
    @objc private func changeResolution()
    {
        if resolution.indexOfSelectedItem == 4 { showSettings(); return }
        let sizes = [(1024, 768), (1280, 800), (1600, 900), (1920, 1080)]
        let size = sizes[max(0, resolution.indexOfSelectedItem)]
        options.width = size.0
        options.height = size.1
        saveSettings()
    }

    @objc private func showSettings()
    {
        guard token == nil, window.attachedSheet == nil else { return }
        options = service.options()
        settingsController = SettingsController(options: options, save:
        { settings in
            try self.service.saveOptions(settings)
            self.options = settings
            self.refresh()
        }, wine:
        {
            self.perform(playing: false) { token, progress in try self.service.configureWine(cancellation: token, progress: progress) }
        })
        settingsController?.show(on: window, installed: service.manifest != nil)
    }

    @objc private func chooseSource()
    {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.title = "Select GOG Game Files"
        if panel.runModal() == .OK { source = panel.url; refresh() }
    }

    @objc private func chooseSaves()
    {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Select Saved Games"
        let legacy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GOG.com/Sid Meier's Alpha Centauri/saves")
        if FileManager.default.fileExists(atPath: legacy.path) { panel.directoryURL = legacy }
        if panel.runModal() == .OK { saves = panel.url; saveImportButton.title = "Saves Selected" }
    }

    @objc private func primaryAction()
    {
        if service.manifest != nil
        {
            let game = selectedGame
            let settings = options
            perform(playing: true) { token, progress in try self.service.play(game, options: settings, cancellation: token, progress: progress) }
        }
        else
        {
            guard let source = source else { return }
            if source.pathExtension.lowercased() == "exe" && !confirm("Install GOG Planetary Pack?", "The installer will use automatic settings. The GOG/EA license applies.", button: "Install") { return }
            let saves = self.saves
            perform(playing: false) { token, progress in try self.service.install(source: source, saves: saves, cancellation: token, progress: progress) }
        }
    }

    private func perform(playing: Bool, work: @escaping (Cancellation, @escaping ProgressHandler) throws -> Void)
    {
        guard token == nil else { return }
        let cancellation = Cancellation()
        token = cancellation
        self.playing = playing
        progress.startAnimation(nil)
        status.stringValue = playing ? "Starting…" : "Preparing…"
        refresh()
        DispatchQueue.global(qos: .userInitiated).async
        {
            var failure: Error?
            do { try work(cancellation) { message in DispatchQueue.main.async { self.status.stringValue = message } } }
            catch { failure = error }
            DispatchQueue.main.async
            {
                self.token = nil
                self.playing = false
                self.options = self.service.options()
                self.progress.stopAnimation(nil)
                self.refresh()
                if let error = failure
                {
                    self.status.stringValue = cancellation.isCancelled ? "Stopped" : "Unable to complete operation"
                    if !cancellation.isCancelled { self.showError(error) }
                }
                else { self.status.stringValue = "Ready" }
                if self.quitWhenFinished { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
    }

    @objc private func stop()
    {
        guard token != nil else { return }
        if playing && !confirm("Stop Game?", "Unsaved progress will be lost.", button: "Stop") { return }
        status.stringValue = "Stopping…"
        token?.cancel()
    }

    @objc private func openSaves()
    {
        if FileManager.default.fileExists(atPath: service.layout.saves.path) { NSWorkspace.shared.open(service.layout.saves) }
    }

    @objc private func openGameFiles()
    {
        let game = service.layout.installation.appendingPathComponent("game")
        if FileManager.default.fileExists(atPath: game.path) { NSWorkspace.shared.open(game) }
    }

    @objc private func openConfiguration()
    {
        guard token == nil else { return }
        let file = service.layout.installation.appendingPathComponent("game/Alpha Centauri.Ini")
        if Files.isRegular(file), let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        {
            NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
            { _, error in
                if let error = error { DispatchQueue.main.async { self.showError(error) } }
            }
        }
    }

    @objc private func exportDiagnostics()
    {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Export Diagnostics"
        if panel.runModal() == .OK, let destination = panel.url
        {
            do { try service.exportDiagnostics(to: destination); NSWorkspace.shared.open(destination) }
            catch { showError(error) }
        }
    }

    @objc private func installRosetta()
    {
        guard token == nil else { return }
        guard confirm("Install Rosetta?", "Continuing accepts Apple's Rosetta software license.", button: "Agree and Install") else { return }
        perform(playing: false)
        { token, progress in
            try self.service.layout.prepare()
            progress("Installing Rosetta…")
            let result = try Commands.run(URL(fileURLWithPath: "/usr/sbin/softwareupdate"), ["--install-rosetta", "--agree-to-license"],
                log: self.service.layout.logs.appendingPathComponent("rosetta.log"), cancellation: token, timeout: 600)
            guard result == 0 else { throw CentauriError.message("Rosetta installation failed.") }
        }
    }

    @objc private func openGOG() { NSWorkspace.shared.open(URL(string: "https://www.gog.com/en/game/sid_meiers_alpha_centauri")!) }
    @objc private func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/drhelius/smac-gog-mac-launcher")!) }
    @objc private func about()
    {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "SMAC Launcher", .applicationVersion: "0.1.0",
            .applicationIcon: Interface.icon ?? NSImage(), .credits: NSAttributedString(string: "Nacho Sánchez · DrHelius")])
    }

    private func confirm(_ title: String, _ message: String, button: String) -> Bool
    {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showError(_ error: Error) { NSAlert(error: error).runModal() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    {
        guard let token = token else { return .terminateNow }
        guard confirm("Quit SMAC Launcher?", playing ? "Unsaved progress will be lost." : "The current operation will be cancelled.", button: "Quit") else { return .terminateCancel }
        quitWhenFinished = true
        token.cancel()
        return .terminateLater
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
if CommandLine.arguments.contains("--render-ui") { app.appearance = NSAppearance(named: .aqua) }
app.setActivationPolicy(CommandLine.arguments.contains("--render-ui") ? .prohibited : .regular)
app.run()
