import AppKit
import CentauriCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate
{
    private let service: CentauriService =
    {
        // Development/acceptance runs can use an isolated root without changing the normal user location.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1)
        {
            return CentauriService(layout: Layout(root: URL(fileURLWithPath: arguments[index + 1], isDirectory: true)))
        }
        return CentauriService()
    }()
    private var window: NSWindow!
    private let sourceField = NSTextField(labelWithString: "Choose your GOG game…")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let installButton = NSButton(title: "Install Game", target: nil, action: nil)
    private let sourceButton = NSButton(title: "Choose…", target: nil, action: nil)
    private let saveImportButton = NSButton(title: "Import Existing Saves…", target: nil, action: nil)
    private let playButton = NSButton(title: "Play", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let gameMenu = NSPopUpButton()
    private let displayMenu = NSPopUpButton()
    private let resolutionMenu = NSPopUpButton()
    private let skipIntro = NSButton(checkboxWithTitle: "Skip opening movie", target: nil, action: nil)
    private var source: URL?
    private var saves: URL?
    private var token: Cancellation?
    private var playing = false
    private var quitWhenFinished = false

    func applicationDidFinishLaunching(_ notification: Notification)
    {
        createMenu()
        createWindow()
        let candidate = URL(fileURLWithPath: "/Applications/Sid Meier's Alpha Centauri Planetary Pack.app")
        if FileManager.default.fileExists(atPath: candidate.path)
        {
            source = candidate
            sourceField.stringValue = candidate.lastPathComponent
        }
        let settings = service.options()
        displayMenu.selectItem(at: settings.windowed ? 0 : 1)
        skipIntro.state = settings.skipIntro ? .on : .off
        if let item = resolutionMenu.itemArray.first(where: { $0.representedObject as? String == "\(settings.width)x\(settings.height)" })
        {
            resolutionMenu.select(item)
        }
        updateControls()
        status.stringValue = service.manifest == nil
            ? "Import your purchased GOG game. First setup downloads the compatibility runtime (about 342 MB); later play works offline."
            : "Ready to play. Your original GOG application is unchanged."
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createMenu()
    {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "About Centauri", action: #selector(about), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Centauri", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        let helpItem = NSMenuItem()
        menu.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Open Saves", action: #selector(openSaves), keyEquivalent: "")
        help.addItem(withTitle: "Open Data Folder", action: #selector(openData), keyEquivalent: "")
        help.addItem(withTitle: "Export Diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: "")
        help.addItem(.separator())
        help.addItem(withTitle: "Install Rosetta…", action: #selector(installRosetta), keyEquivalent: "")
        help.addItem(withTitle: "GOG Download Page", action: #selector(openGOG), keyEquivalent: "")
        helpItem.submenu = help
        NSApp.mainMenu = menu
    }

    private func createWindow()
    {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: 570),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Centauri"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)
        ])
        let title = NSTextField(labelWithString: "Centauri")
        title.font = .systemFont(ofSize: 32, weight: .bold)
        content.addArrangedSubview(title)
        let subtitle = NSTextField(labelWithString: "Alpha Centauri and Alien Crossfire for your Mac")
        subtitle.textColor = .secondaryLabelColor
        content.addArrangedSubview(subtitle)
        content.addArrangedSubview(separator())

        let sourceTitle = NSTextField(labelWithString: "Your GOG game")
        sourceTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        content.addArrangedSubview(sourceTitle)
        sourceField.lineBreakMode = .byTruncatingMiddle
        sourceField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sourceButton.target = self
        sourceButton.action = #selector(chooseSource)
        content.addArrangedSubview(row([sourceField, sourceButton]))
        installButton.bezelStyle = .rounded
        installButton.target = self
        installButton.action = #selector(install)
        saveImportButton.bezelStyle = .rounded
        saveImportButton.target = self
        saveImportButton.action = #selector(chooseSaves)
        content.addArrangedSubview(row([installButton, saveImportButton]))
        content.addArrangedSubview(separator())

        gameMenu.addItems(withTitles: Game.allCases.map(\.title))
        displayMenu.addItems(withTitles: ["Window", "Fullscreen"])
        displayMenu.target = self
        displayMenu.action = #selector(displayChanged)
        var resolutions = [(1024, 768), (1280, 800), (1600, 900), (1920, 1080)]
        if let screen = NSScreen.main
        {
            let size = (Int(screen.frame.width), Int(screen.frame.height))
            if size.0 >= 800 && size.1 >= 600 && !resolutions.contains(where: { $0 == size }) { resolutions.append(size) }
        }
        for (width, height) in resolutions
        {
            resolutionMenu.addItem(withTitle: "\(width) × \(height)")
            resolutionMenu.lastItem?.representedObject = "\(width)x\(height)"
        }
        content.addArrangedSubview(row([NSTextField(labelWithString: "Game"), gameMenu]))
        content.addArrangedSubview(row([NSTextField(labelWithString: "Display"), displayMenu, resolutionMenu]))
        content.addArrangedSubview(skipIntro)

        playButton.bezelStyle = .rounded
        playButton.keyEquivalent = "\r"
        playButton.target = self
        playButton.action = #selector(play)
        stopButton.bezelStyle = .rounded
        stopButton.target = self
        stopButton.action = #selector(stop)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        let savesButton = NSButton(title: "Open Saves", target: self, action: #selector(openSaves))
        savesButton.bezelStyle = .rounded
        content.addArrangedSubview(row([playButton, stopButton, progress, savesButton]))
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.preferredMaxLayoutWidth = 570
        content.addArrangedSubview(status)
        let preview = NSTextField(labelWithString: "Development preview · Gameplay validation in progress")
        preview.font = .systemFont(ofSize: 10)
        preview.textColor = .tertiaryLabelColor
        content.addArrangedSubview(preview)
    }

    private func row(_ views: [NSView]) -> NSStackView
    {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return stack
    }

    private func separator() -> NSBox
    {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 574).isActive = true
        return box
    }

    @objc private func chooseSource()
    {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Choose your old GOG Mac app, game folder, or Windows offline setup .exe. Keep all installer .bin files in the same folder."
        if panel.runModal() == .OK, let url = panel.url
        {
            source = url
            sourceField.stringValue = url.lastPathComponent
            updateControls()
        }
    }

    @objc private func chooseSaves()
    {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Optionally choose an existing saves folder. Saves are copied into an Imported subfolder; originals are preserved."
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GOG.com/Sid Meier's Alpha Centauri/saves")
        if FileManager.default.fileExists(atPath: legacy.path) { panel.directoryURL = legacy }
        if panel.runModal() == .OK
        {
            saves = panel.url
            saveImportButton.title = "Existing Saves Selected"
        }
    }

    @objc private func install()
    {
        guard let source = source else { return }
        if source.pathExtension.lowercased() == "exe"
        {
            guard confirm("Install your GOG download?",
                "Centauri will run this installer with automatic settings. Use only the offline installer from your GOG library. The game remains subject to its GOG/EA license agreement.", button: "Install") else { return }
        }
        let saves = self.saves
        perform(playing: false)
        { token, progress in
            try self.service.install(source: source, saves: saves, cancellation: token, progress: progress)
        }
    }

    @objc private func play()
    {
        let game = Game.allCases[max(0, gameMenu.indexOfSelectedItem)]
        var options = PlayOptions()
        options.windowed = displayMenu.indexOfSelectedItem == 0
        options.skipIntro = skipIntro.state == .on
        let size = (resolutionMenu.selectedItem?.representedObject as? String ?? "1024x768").split(separator: "x")
        options.width = Int(size[0]) ?? 1024
        options.height = Int(size[1]) ?? 768
        perform(playing: true)
        { token, progress in
            try self.service.play(game, options: options, cancellation: token, progress: progress)
        }
    }

    private func perform(playing: Bool, work: @escaping (Cancellation, @escaping ProgressHandler) throws -> Void)
    {
        guard token == nil else { return }
        let cancellation = Cancellation()
        token = cancellation
        self.playing = playing
        progress.startAnimation(nil)
        status.stringValue = playing ? "Starting the game…" : "Preparing installation…"
        updateControls()
        DispatchQueue.global(qos: .userInitiated).async
        {
            var failure: Error?
            do
            {
                try work(cancellation)
                { message in DispatchQueue.main.async { self.status.stringValue = message } }
            }
            catch { failure = error }
            DispatchQueue.main.async
            {
                self.token = nil
                self.playing = false
                self.progress.stopAnimation(nil)
                self.updateControls()
                if let error = failure
                {
                    self.status.stringValue = error.localizedDescription
                    if !cancellation.isCancelled { self.showError(error) }
                }
                if self.quitWhenFinished { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
    }

    @objc private func stop()
    {
        guard token != nil else { return }
        if playing && !confirm("Stop the game?", "Any unsaved progress will be lost. Use the game's own Quit command after saving whenever possible.", button: "Stop Game") { return }
        status.stringValue = "Stopping this session…"
        token?.cancel()
    }

    @objc private func displayChanged() { updateControls() }

    private func updateControls()
    {
        let busy = token != nil
        let installed = service.manifest != nil
        installButton.isEnabled = !busy && !installed && source != nil
        installButton.title = installed ? "Installed" : "Install Game"
        sourceButton.isEnabled = !busy && !installed
        saveImportButton.isEnabled = !busy && !installed
        playButton.isEnabled = !busy && installed
        stopButton.isEnabled = busy
        stopButton.title = playing ? "Stop Game" : "Cancel"
        gameMenu.isEnabled = !busy
        displayMenu.isEnabled = !busy
        resolutionMenu.isEnabled = !busy && displayMenu.indexOfSelectedItem == 0
        skipIntro.isEnabled = !busy
    }

    @objc private func openSaves()
    {
        if FileManager.default.fileExists(atPath: service.layout.saves.path) { NSWorkspace.shared.open(service.layout.saves) }
    }

    @objc private func openData()
    {
        do { try service.layout.prepare(); NSWorkspace.shared.open(service.layout.root) }
        catch { showError(error) }
    }

    @objc private func exportDiagnostics()
    {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose where to export version information and recent logs. No saves or game assets are included. Review logs before sharing; they may contain file names."
        if panel.runModal() == .OK, let destination = panel.url
        {
            do { try service.exportDiagnostics(to: destination); NSWorkspace.shared.open(destination) }
            catch { showError(error) }
        }
    }

    @objc private func installRosetta()
    {
        guard token == nil else { return }
        guard confirm("Install Apple's Rosetta?", "Apple Silicon needs Rosetta to run Wine. Continuing accepts Apple's Rosetta software license. You can review Apple's installation information first at support.apple.com/102527.", button: "Agree and Install") else { return }
        perform(playing: false)
        { token, progress in
            try self.service.layout.prepare()
            progress("Installing Rosetta through Apple…")
            let result = try Commands.run(URL(fileURLWithPath: "/usr/sbin/softwareupdate"),
                ["--install-rosetta", "--agree-to-license"], log: self.service.layout.logs.appendingPathComponent("rosetta.log"),
                cancellation: token, timeout: 600)
            guard result == 0 else { throw CentauriError.message("Rosetta installation failed. See Apple's installation instructions in Help.") }
            progress("Rosetta is installed. You can install or launch the game now.")
        }
    }

    @objc private func openGOG()
    {
        NSWorkspace.shared.open(URL(string: "https://www.gog.com/en/game/sid_meiers_alpha_centauri")!)
    }

    @objc private func about()
    {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Centauri", .applicationVersion: "0.1.0 Development Preview",
            .credits: NSAttributedString(string: "An open-source launcher by Nacho Sánchez (DrHelius).\nRequires your own GOG Planetary Pack.\nNot affiliated with Firaxis, EA or GOG.")
        ])
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

    private func showError(_ error: Error)
    {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    {
        guard let token = token else { return .terminateNow }
        guard confirm("Quit Centauri?", playing ? "This will stop the game. Unsaved progress will be lost." : "This will cancel the current operation.", button: "Quit") else { return .terminateCancel }
        quitWhenFinished = true
        token.cancel()
        return .terminateLater
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool
    {
        NSApp.terminate(nil)
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
