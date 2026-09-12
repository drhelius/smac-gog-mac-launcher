import AppKit
import CentauriCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation
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
    private var profileController: ProfileController?
    private var profiles: [LaunchProfile] = []
    private var selectedProfileID = ""
    private var selectedProfile: LaunchProfile? { profiles.first { $0.id == selectedProfileID && $0.game == selectedGame } }
    private let profilePicker = NSPopUpButton()
    private let modActions = NSPopUpButton(frame: .zero, pullsDown: true)
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
    private var advancedButton: NSButton!
    private var savesButton: NSButton!
    private var filesButton: NSButton!
    private let display = NSSegmentedControl(labels: ["Fullscreen", "Window"], trackingMode: .selectOne, target: nil, action: nil)
    private let resolution = NSPopUpButton()
    private var resolutionSizes = [(1024, 768), (1280, 800), (1600, 900), (1920, 1080)]
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
        reloadProfiles()
        options = service.options(profile: selectedProfile)
        let candidate = URL(fileURLWithPath: "/Applications/Sid Meier's Alpha Centauri Planetary Pack.app")
        if FileManager.default.fileExists(atPath: candidate.path) { source = candidate }
        createMenu()
        createWindow()
        refresh()
        status.stringValue = ""
        status.isHidden = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification)
    {
        guard window != nil, token == nil, window.attachedSheet == nil else { return }
        reloadProfiles()
        options = service.options(profile: selectedProfile)
        refresh()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
    {
        switch menuItem.action
        {
        case #selector(newProfile):
            return token == nil && service.manifest != nil && window?.attachedSheet == nil
        case #selector(editProfile), #selector(addModFiles), #selector(runModInstaller), #selector(removeProfile):
            return token == nil && selectedProfile != nil && window?.attachedSheet == nil
        case #selector(showSettings), #selector(installRosetta):
            return token == nil && window?.attachedSheet == nil
        case #selector(openConfiguration):
            return token == nil && service.manifest != nil
        case #selector(openSaves), #selector(openGameFiles):
            return service.manifest != nil
        default:
            return true
        }
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
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "SMAC Launcher"
        window.contentMinSize = NSSize(width: 900, height: 700)
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
        brandIcon.wantsLayer = true
        brandIcon.layer?.cornerRadius = 9
        brandIcon.layer?.masksToBounds = true
        brandIcon.imageScaling = .scaleProportionallyUpOrDown
        brandIcon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        brandIcon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let brandText = Interface.stack([Interface.label("SMAC Launcher", size: 16, weight: .semibold), Interface.label(BuildInfo.version, size: 11, color: .secondaryLabelColor)], spacing: 3)
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
        savesButton = Interface.button("Saved Games", symbol: "folder", target: self, action: #selector(openSaves))
        filesButton = Interface.button("Game Files", symbol: "folder.badge.gearshape", target: self, action: #selector(openGameFiles))
        let bottom = Interface.stack([savesButton!, filesButton!, settingsButton, Interface.label("DrHelius", size: 10, color: .tertiaryLabelColor)], spacing: 12)
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
        advancedButton = Interface.button("Advanced Settings…", target: self, action: #selector(showSettings))
        profilePicker.target = self
        profilePicker.action = #selector(changeProfile)
        profilePicker.widthAnchor.constraint(equalToConstant: 225).isActive = true
        profilePicker.setAccessibilityLabel("Game configuration")
        modActions.addItem(withTitle: "Mods")
        for (title, action) in [("New Configuration…", #selector(newProfile)), ("Edit Configuration…", #selector(editProfile)),
                                ("Install from Folder…", #selector(addModFiles)), ("Run Installer (.exe)…", #selector(runModInstaller)),
                                ("Remove Configuration…", #selector(removeProfile))]
        {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if action == #selector(addModFiles) { item.toolTip = "Copy an extracted mod folder's contents into the selected configuration. Matching files are replaced in that configuration only." }
            if action == #selector(runModInstaller) { item.toolTip = "Run a Windows .exe mod installer in the selected configuration. Choose C:\\SMAC as its destination." }
            modActions.menu?.addItem(item)
        }
        displayGrid = NSGridView(views: [
            [Interface.label("Configuration"), Interface.stack([profilePicker, modActions], vertical: false)],
            [Interface.label("Display"), display],
            [Interface.label("Window size"), resolution],
            [Interface.label("Opening movie"), openingMovie],
            [NSView(), advancedButton!]
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
        primary.font = .systemFont(ofSize: 17, weight: .semibold)
        primary.keyEquivalent = "\r"
        primary.target = self
        primary.action = #selector(primaryAction)
        primary.widthAnchor.constraint(equalToConstant: 240).isActive = true
        primary.heightAnchor.constraint(equalToConstant: 52).isActive = true
        stopButton.title = "Stop"
        stopButton.bezelStyle = .rounded
        stopButton.target = self
        stopButton.action = #selector(stop)
        let actions = NSView()
        primary.translatesAutoresizingMaskIntoConstraints = false
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        actions.addSubview(primary)
        actions.addSubview(stopButton)
        NSLayoutConstraint.activate([
            actions.heightAnchor.constraint(equalToConstant: 52),
            primary.centerXAnchor.constraint(equalTo: actions.centerXAnchor),
            primary.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
            stopButton.leadingAnchor.constraint(equalTo: primary.trailingAnchor, constant: 14),
            stopButton.centerYAnchor.constraint(equalTo: actions.centerYAnchor)
        ])
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
        actions.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
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
        advancedButton.isEnabled = !busy
        savesButton.isEnabled = installed
        filesButton.isEnabled = installed
        profilePicker.isEnabled = !busy && installed
        modActions.isEnabled = !busy && installed
        let plan = try? LaunchPlan.resolve(directory: service.gameDirectory(profile: selectedProfile), game: selectedGame, profile: selectedProfile)
        resolutionSizes = [(1024, 768), (1280, 800), (1600, plan?.integration == .thinker ? 896 : 900), (1920, 1080)]
        let titles = resolutionSizes.map { "\($0.0) × \($0.1)" } + ["Custom…"]
        if resolution.itemTitles != titles { resolution.removeAllItems(); resolution.addItems(withTitles: titles) }
        displayGrid.row(at: 0).isHidden = !installed
        displayGrid.row(at: 1).isHidden = installed && plan?.managesDisplay != true
        display.isEnabled = !busy
        resolution.isEnabled = !busy
        openingMovie.isEnabled = !busy && options.moviesEnabled && (!installed || plan?.nativeMovies == true)
        openingMovie.toolTip = plan?.nativeMovies == false ? "Movie playback is controlled by the selected mod." : nil
        display.selectedSegment = options.windowed ? 1 : 0
        displayGrid.row(at: 2).isHidden = !options.windowed || (installed && plan?.managesDisplay != true)
        openingMovie.state = options.skipIntro ? .off : .on
        let size = "\(options.width) × \(options.height)"
        if resolution.itemTitles.contains(size) { resolution.selectItem(withTitle: size) }
        else { resolution.selectItem(withTitle: "Custom…") }
    }

    private func reloadProfiles()
    {
        profiles = service.profiles().filter { $0.game == selectedGame }
        selectedProfileID = UserDefaults.standard.string(forKey: "profile-" + selectedGame.rawValue) ?? ""
        profilePicker.removeAllItems()
        profilePicker.addItem(withTitle: "Original")
        profilePicker.addItems(withTitles: profiles.map(\.name))
        if let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) { profilePicker.selectItem(at: index + 1) }
        else { selectedProfileID = ""; profilePicker.selectItem(at: 0) }
    }

    private func selectProfile(_ profile: LaunchProfile)
    {
        UserDefaults.standard.set(profile.id, forKey: "profile-" + selectedGame.rawValue)
        reloadProfiles()
        options = service.options(profile: selectedProfile)
        refresh()
    }

    @objc private func changeProfile()
    {
        let index = profilePicker.indexOfSelectedItem - 1
        selectedProfileID = profiles.indices.contains(index) ? profiles[index].id : ""
        UserDefaults.standard.set(selectedProfileID, forKey: "profile-" + selectedGame.rawValue)
        options = service.options(profile: selectedProfile)
        refresh()
    }

    @objc private func newProfile()
    {
        guard token == nil, service.manifest != nil else { return }
        let alert = NSAlert()
        alert.messageText = "New Mod Configuration"
        let name = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        name.placeholderString = "Configuration name"
        alert.accessoryView = name
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let game = selectedGame
        var created: LaunchProfile?
        perform(playing: false, completion:
        {
            if let profile = created { self.selectProfile(profile); self.editProfile() }
        })
        { token, progress in
            created = try self.service.createProfile(name: title, game: game, cancellation: token, progress: progress)
        }
    }

    @objc private func editProfile()
    {
        guard token == nil, window.attachedSheet == nil, let profile = selectedProfile else { return }
        do
        {
            profileController = ProfileController(profile: profile, directory: try service.gameDirectory(profile: profile))
            { updated in
                try self.service.saveProfile(updated)
                self.selectProfile(updated)
            }
            profileController?.show(on: window)
        }
        catch { showError(error) }
    }

    private func suggestExecutable(_ profile: LaunchProfile) throws
    {
        let directory = try service.gameDirectory(profile: profile)
        let names = LaunchPlan.executables(in: directory)
        let candidates = (profile.game == .alienCrossfire ? ["thinker.exe"] : []) +
            [profile.game.rawValue.replacingOccurrences(of: ".exe", with: "_PRACX.exe")]
        if let executable = candidates.compactMap({ candidate in names.first { $0.caseInsensitiveCompare(candidate) == .orderedSame } }).first,
           profile.executable.isEmpty || profile.executable == profile.game.rawValue
        {
            var updated = profile
            updated.executable = executable
            try service.saveProfile(updated)
        }
    }

    @objc private func removeProfile()
    {
        guard let profile = selectedProfile, token == nil else { return }
        guard confirm("Move \(profile.name) to Trash?", "This includes this configuration's mod files and saved games.", button: "Move to Trash") else { return }
        do
        {
            try service.removeProfile(profile)
            reloadProfiles()
            options = service.options(profile: selectedProfile)
            refresh()
        }
        catch { showError(error) }
    }

    @objc private func addModFiles()
    {
        guard let profile = selectedProfile, token == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the Extracted Mod Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        perform(playing: false, completion: { self.editProfile() })
        { token, progress in
            try self.service.addModFiles(source, profile: profile, cancellation: token, progress: progress)
            try self.suggestExecutable(profile)
        }
    }

    @objc private func runModInstaller()
    {
        guard let profile = selectedProfile, token == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Windows Mod Installer"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let installer = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Run Windows Mod Installer"
        alert.informativeText = "Choose C:\\SMAC as the destination in the installer."
        let arguments = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        arguments.placeholderString = "Optional installer arguments"
        alert.accessoryView = arguments
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let parameters = arguments.stringValue
        perform(playing: false, completion: { self.editProfile() })
        { token, progress in
            try self.service.installMod(installer, profile: profile, arguments: parameters, cancellation: token, progress: progress)
            try self.suggestExecutable(profile)
        }
    }

    @objc private func selectGame(_ button: GameButton)
    {
        selectedGame = button.game
        UserDefaults.standard.set(Game.allCases.firstIndex(of: selectedGame) ?? 0, forKey: "selectedGame")
        reloadProfiles()
        options = service.options(profile: selectedProfile)
        refresh()
    }

    private func saveSettings()
    {
        do { try service.saveOptions(options, profile: selectedProfile) }
        catch { options = service.options(profile: selectedProfile); showError(error) }
        refresh()
    }

    @objc private func changeDisplay() { options.windowed = display.selectedSegment == 1; saveSettings() }
    @objc private func changeOpeningMovie() { options.skipIntro = openingMovie.state != .on; saveSettings() }
    @objc private func changeResolution()
    {
        if resolution.indexOfSelectedItem == 4 { showSettings(); refresh(); return }
        let size = resolutionSizes[max(0, resolution.indexOfSelectedItem)]
        options.width = size.0
        options.height = size.1
        saveSettings()
    }

    @objc private func showSettings()
    {
        guard token == nil, window.attachedSheet == nil else { return }
        options = service.options(profile: selectedProfile)
        let profile = selectedProfile
        let plan = try? LaunchPlan.resolve(directory: service.gameDirectory(profile: profile), game: selectedGame, profile: profile)
        settingsController = SettingsController(options: options,
            managesDisplay: service.manifest == nil || plan?.managesDisplay == true,
            managesSettings: service.manifest == nil || plan?.managesSettings == true,
            nativeMovies: service.manifest == nil || plan?.nativeMovies == true,
            windowHeightAlignment: plan?.integration == .thinker && plan?.usesPRACX == false ? 8 : 1, save:
        { settings in
            try self.service.saveOptions(settings, profile: profile)
            self.options = settings
            self.refresh()
        }, wine:
        {
            self.perform(playing: false) { token, progress in try self.service.configureWine(profile: profile, cancellation: token, progress: progress) }
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
            let profile = selectedProfile
            perform(playing: true) { token, progress in try self.service.play(game, options: settings, profile: profile, cancellation: token, progress: progress) }
        }
        else
        {
            guard let source = source else { return }
            if source.pathExtension.lowercased() == "exe" && !confirm("Install GOG Planetary Pack?", "The installer will use automatic settings. The GOG/EA license applies.", button: "Install") { return }
            let saves = self.saves
            perform(playing: false) { token, progress in try self.service.install(source: source, saves: saves, cancellation: token, progress: progress) }
        }
    }

    private func perform(playing: Bool, completion: (() -> Void)? = nil,
                         work: @escaping (Cancellation, @escaping ProgressHandler) throws -> Void)
    {
        guard token == nil else { return }
        let cancellation = Cancellation()
        token = cancellation
        self.playing = playing
        progress.startAnimation(nil)
        status.stringValue = playing ? "Starting…" : "Preparing…"
        status.isHidden = false
        refresh()
        DispatchQueue.global(qos: .userInitiated).async
        {
            var failure: Error?
            do
            {
                try work(cancellation)
                { message in
                    DispatchQueue.main.async
                    {
                        self.status.stringValue = message == "Ready" ? "" : message
                        self.status.isHidden = self.status.stringValue.isEmpty
                    }
                }
            }
            catch { failure = error }
            DispatchQueue.main.async
            {
                self.token = nil
                self.playing = false
                self.reloadProfiles()
                self.options = self.service.options(profile: self.selectedProfile)
                self.progress.stopAnimation(nil)
                self.refresh()
                self.status.stringValue = ""
                self.status.isHidden = true
                if let error = failure
                {
                    if !cancellation.isCancelled { self.showError(error) }
                }
                else { completion?() }
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
        if let game = try? service.gameDirectory(profile: selectedProfile)
        {
            let working = (try? LaunchPlan.directory(in: game, relative: selectedProfile?.workingDirectory ?? "")) ?? game
            NSWorkspace.shared.open(working.appendingPathComponent("saves"))
        }
    }

    @objc private func openGameFiles()
    {
        if let game = try? service.gameDirectory(profile: selectedProfile) { NSWorkspace.shared.open(game) }
    }

    @objc private func openConfiguration()
    {
        guard token == nil else { return }
        guard let game = try? service.gameDirectory(profile: selectedProfile) else { return }
        let working = (try? LaunchPlan.directory(in: game, relative: selectedProfile?.workingDirectory ?? "")) ?? game
        let file = working.appendingPathComponent("Alpha Centauri.Ini")
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
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "SMAC Launcher", .applicationVersion: BuildInfo.version,
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
app.setActivationPolicy(.regular)
app.run()
