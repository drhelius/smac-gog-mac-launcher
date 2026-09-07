import AppKit
import AVKit

final class MovieWindow: NSWindow
{
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect
    {
        // Borderless cutscenes cover the menu-bar/notch region as well as the visible desktop.
        frameRect
    }
}

final class MovieDelegate: NSObject, NSApplicationDelegate
{
    var window: NSWindow!
    var player: AVPlayer!
    var observations: [NSObjectProtocol] = []
    var statusObservation: NSKeyValueObservation?
    var result: Int32 = 0

    func applicationDidFinishLaunching(_ notification: Notification)
    {
        guard CommandLine.arguments.count == 2 || (CommandLine.arguments.count == 4 && CommandLine.arguments[2] == "--volume") else { finish(2); return }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        if CommandLine.arguments.count == 4
        {
            player.volume = Float(min(100, max(0, Int(CommandLine.arguments[3]) ?? 100))) / 100
        }
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = MovieWindow(contentRect: screen, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.isOpaque = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .screenSaver
        let view = AVPlayerView(frame: NSRect(origin: .zero, size: screen.size))
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        let skip = NSButton(title: "Skip  ⎋", target: self, action: #selector(skipMovie))
        skip.bezelStyle = .rounded
        skip.keyEquivalent = "\u{1b}"
        skip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(skip)
        NSLayoutConstraint.activate([
            skip.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            skip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in self.finish(0) })
        observations.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { _ in self.finish(2) })
        statusObservation = item.observe(\.status, options: [.new])
        { item, _ in
            if item.status == .failed
            {
                fputs("Movie playback failed: \(item.error?.localizedDescription ?? "unknown error")\n", stderr)
                DispatchQueue.main.async { self.finish(2) }
            }
        }
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        window.setFrame(screen, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        player.play()
    }

    @objc func skipMovie() { finish(0) }

    func finish(_ status: Int32)
    {
        result = status
        player?.pause()
        NSApp.stop(nil)
        // Wake the event loop after stop when completion arrives from an asynchronous notification.
        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)
        if let event = event { NSApp.postEvent(event, atStart: false) }
    }
}

let app = NSApplication.shared
let delegate = MovieDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
exit(delegate.result)
