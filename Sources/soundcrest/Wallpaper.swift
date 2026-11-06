import AppKit
import Darwin
import QuartzCore
import WaveCore

enum Wallpaper {
    private static let lockPath = NSTemporaryDirectory() + "soundcrest-wallpaper.lock"

    /// The running background holds this lock for its whole life.
    static var isRunning: Bool {
        let probe = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        return flock(probe, LOCK_EX | LOCK_NB) != 0
    }

    /// Ends the running background and waits for its lock to clear.
    static func stop() {
        guard let text = try? String(contentsOfFile: lockPath, encoding: .utf8),
              let pid = pid_t(text), kill(pid, SIGTERM) == 0 else { return }
        for _ in 0..<40 where isRunning { usleep(50_000) }
    }

    /// Starts the background in its own session so it outlives this terminal.
    static func launch(_ look: Look) {
        guard let path = Bundle.main.executablePath else { exit(1) }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", O_RDWR, 0)
        }

        var pid: pid_t = 0
        var arguments: [UnsafeMutablePointer<CChar>?] = [
            strdup(path), strdup("--wallpaper-run"),
            strdup("--color"), strdup(look.color),
            strdup("--backdrop"), strdup(look.backdrop.rawValue),
            nil,
        ]
        var environment: [UnsafeMutablePointer<CChar>?] =
            ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let status = posix_spawn(&pid, path, &actions, &attributes, &arguments, &environment)
        guard status == 0 else {
            FileHandle.standardError.write(Data("soundcrest: could not start (\(status))\n".utf8))
            exit(1)
        }
    }

    @MainActor static func run(_ look: Look) -> Never {
        signal(SIGHUP, SIG_IGN)
        // Held for the life of the process; the kernel frees it on exit.
        let lock = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
        ftruncate(lock, 0)
        _ = "\(getpid())".withCString { write(lock, $0, strlen($0)) }

        let app = NSApplication.shared
        let delegate = WallpaperApp(look: look)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        exit(0)
    }
}

/// One desktop-level window per display. It sits above the picture and below
/// the icons, and never takes clicks or focus.
@MainActor private final class WaveWindow {
    private static let tint = NSColor(srgbRed: 0.03, green: 0.03, blue: 0.06, alpha: 1)
    private static let reachOfHeight: CGFloat = 0.36
    private static let restingLine: CGFloat = 1

    private let window: NSWindow
    private let mask = CAShapeLayer()

    init(screen: NSScreen, look: Look) {
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.isOpaque = look.backdrop == .solid
        window.backgroundColor = Self.tint.withAlphaComponent(CGFloat(look.backdrop.alpha))

        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = host.bounds
        let centre = NSColor(look.palette.centre).cgColor
        let edge = NSColor(look.palette.edge).cgColor
        gradient.colors = [edge, centre, edge]
        gradient.mask = mask
        mask.frame = host.bounds
        mask.contentsScale = screen.backingScaleFactor
        mask.fillColor = NSColor.white.cgColor
        host.layer?.addSublayer(gradient)
        window.contentView = host
        window.orderBack(nil)
    }

    func close() { window.close() }

    func draw(heights: [Float]) {
        guard heights.count > 1 else { return }
        let size = mask.bounds.size
        let mid = size.height / 2
        let reach = size.height * Self.reachOfHeight
        let step = size.width / CGFloat(heights.count - 1)
        let offsets = heights.map { CGFloat($0) * reach + Self.restingLine }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: mid + offsets[0]))
        for (i, offset) in offsets.enumerated() {
            path.addLine(to: CGPoint(x: CGFloat(i) * step, y: mid + offset))
        }
        for (i, offset) in offsets.enumerated().reversed() {
            path.addLine(to: CGPoint(x: CGFloat(i) * step, y: mid - offset))
        }
        path.closeSubpath()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.path = path
        CATransaction.commit()
    }
}

private extension NSColor {
    convenience init(_ color: RGB) {
        self.init(srgbRed: CGFloat(color.r / 255), green: CGFloat(color.g / 255),
                  blue: CGFloat(color.b / 255), alpha: 1)
    }
}

@MainActor private final class WallpaperApp: NSObject, NSApplicationDelegate {
    private static let bandCount = 96
    private static let columnCount = 320
    /// Below this the display reads as flat, so redraws are skipped to save power.
    private static let settledLevel: Float = 0.002
    private static let ticksPerSecond = 60
    private static let tapChecksPerSecond = 4
    private static let tapHoldSeconds = 5.0

    private let look: Look
    private let ring = SampleRing(capacity: 1 << 16)
    private let analyzer = Analyzer()
    private lazy var tap = SystemAudioTap(ring: ring)
    private var samples = [Float](repeating: 0, count: Analyzer.fftSize)
    private var windows: [WaveWindow] = []
    private var statusItem: NSStatusItem?
    private var settled = false
    private var tickNumber = 0
    private var gate = TapGate(hold: WallpaperApp.tapHoldSeconds)
    private var loggedTapFailure = false

    init(look: Look) { self.look = look }

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKey.install()
        installStatusItem()
        rebuildWindows()
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildWindows),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let timer = Timer(timeInterval: 1 / Double(Self.ticksPerSecond), target: self,
                          selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) { tap.stop() }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "soundcrest")
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Turn Off soundcrest", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "w")
        quit.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { WaveWindow(screen: $0, look: look) }
        settled = false
    }

    @objc private func tick() {
        tickNumber += 1
        if tickNumber % (Self.ticksPerSecond / Self.tapChecksPerSecond) == 0 { updateTap() }
        if !tap.isRunning && settled { return }

        ring.readLatest(into: &samples)
        let levels = analyzer.bands(samples: samples, count: Self.bandCount, sampleRate: tap.sampleRate)
        let quiet = (levels.max() ?? 0) < Self.settledLevel
        if quiet && settled { return }
        settled = quiet

        let heights = Silhouette.heights(levels: levels, columns: Self.columnCount)
        windows.forEach { $0.draw(heights: heights) }
    }

    /// Runs the tap only while something plays, so an idle Mac can sleep.
    private func updateTap() {
        let wanted = gate.update(outputActive: otherProcessIsPlaying(),
                                 now: ProcessInfo.processInfo.systemUptime)
        if tap.isRunning {
            // Reopened below, which also follows a new default output device.
            let moved = (try? defaultOutputDevice()).map { $0 != tap.outputDevice } ?? false
            if !wanted || moved {
                tap.stop()
                ring.clear()
            }
        }
        guard wanted, !tap.isRunning else { return }
        do {
            try tap.start()
            loggedTapFailure = false
        } catch {
            if !loggedTapFailure { NSLog("soundcrest: %@", error.localizedDescription) }
            loggedTapFailure = true
        }
    }
}
