import AppKit
import CentauriCore

final class ProfileController: NSObject
{
    private var profile: LaunchProfile
    private let directory: URL
    private let save: (LaunchProfile) throws -> Void
    private var window: NSWindow!
    private let name = NSTextField()
    private let executable = NSComboBox()
    private let arguments = NSTextField()
    private let workingDirectory = NSTextField()
    private let integration = NSPopUpButton()

    init(profile: LaunchProfile, directory: URL, save: @escaping (LaunchProfile) throws -> Void)
    {
        self.profile = profile
        self.directory = directory
        self.save = save
    }

    func show(on parent: NSWindow)
    {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Mod Configuration"
        window.isReleasedWhenClosed = false
        name.stringValue = profile.name
        executable.addItems(withObjectValues: LaunchPlan.executables(in: directory))
        executable.stringValue = profile.executable.isEmpty ? profile.game.rawValue : profile.executable
        executable.widthAnchor.constraint(equalToConstant: 340).isActive = true
        executable.toolTip = "Executable relative to this configuration's game folder."
        arguments.stringValue = profile.arguments
        arguments.placeholderString = "Optional arguments"
        arguments.toolTip = "Arguments are passed directly to the executable. Use quotes around values containing spaces."
        workingDirectory.stringValue = profile.workingDirectory ?? ""
        workingDirectory.placeholderString = "Game folder"
        workingDirectory.toolTip = "Optional subfolder relative to this configuration's game folder. Leave empty to use the game folder."
        integration.addItems(withTitles: LaunchIntegration.allCases.map(\.title))
        integration.selectItem(at: LaunchIntegration.allCases.firstIndex(of: profile.integration) ?? 0)
        integration.toolTip = "Selects the launcher's compatibility behavior; it does not install a mod. Leave Automatic selected unless you need an override. Custom uses the mod's own settings."
        let choose = Interface.button("Choose…", target: self, action: #selector(chooseExecutable))
        let grid = NSGridView(views: [
            [Interface.label("Name"), name],
            [Interface.label("Executable"), Interface.stack([executable, choose], vertical: false)],
            [Interface.label("Arguments"), arguments],
            [Interface.label("Working folder"), workingDirectory],
            [Interface.label("Compatibility mode"), integration]
        ])
        grid.column(at: 0).width = 135
        grid.columnSpacing = 20
        grid.rowSpacing = 18
        grid.yPlacement = .center
        name.widthAnchor.constraint(equalToConstant: 340).isActive = true
        arguments.widthAnchor.constraint(equalToConstant: 340).isActive = true
        workingDirectory.widthAnchor.constraint(equalToConstant: 340).isActive = true
        let cancel = Interface.button("Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let apply = Interface.button("Save", target: self, action: #selector(apply))
        apply.keyEquivalent = "\r"
        let footer = Interface.stack([NSView(), cancel, apply], vertical: false)
        let content = Interface.stack([grid, footer], spacing: 28)
        Interface.inset(content, in: window.contentView!, amount: 24)
        footer.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        parent.beginSheet(window)
    }

    @objc private func chooseExecutable()
    {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = directory
        panel.title = "Choose Mod Executable"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        let root = directory.standardizedFileURL.path + "/"
        guard file.standardizedFileURL.path.hasPrefix(root) else
        {
            NSAlert(error: CentauriError.message("Add the mod's files to this configuration first, then choose its executable.")).runModal()
            return
        }
        executable.stringValue = String(file.standardizedFileURL.path.dropFirst(root.count))
    }

    @objc private func apply()
    {
        profile.name = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.executable = executable.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.arguments = arguments.stringValue
        profile.workingDirectory = workingDirectory.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.integration = LaunchIntegration.allCases[max(0, integration.indexOfSelectedItem)]
        do
        {
            try profile.validate()
            try save(profile)
            cancel()
        }
        catch { NSAlert(error: error).runModal() }
    }

    @objc private func cancel() { window.sheetParent?.endSheet(window); window.orderOut(nil) }
}
