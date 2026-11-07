import Darwin
import Foundation
import WaveCore

/// Runs inside the new window: `--pane-shell` lays it out, `--pane-run` draws.
enum Pane {
    private static let framesPerSecond: UInt32 = 30
    private static let tapChecksPerSecond = 2
    private static let idleSeconds = 0.25
    private static let settledLevel: Float = 0.002

    /// Never leaves the window without a shell, whatever goes wrong.
    static func openShell() -> Never {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let tmux = findTmux(), let path = Bundle.main.executablePath, let paneCols = columns() {
            let arguments = PaneLayout.tmuxArguments(
                tmux: tmux, shell: shell, executable: LoginItem.stablePath(path), paneCols: paneCols)
            exec(tmux, arguments)
        }
        setenv("SOUNDCREST_NO_PANE", "1", 1)
        exec(shell, ["-l"])
        exit(1)
    }

    private static func exec(_ path: String, _ arguments: [String]) {
        var argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) } + [nil]
        execv(path, &argv)
    }

    private static func columns() -> Int? {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 else { return nil }
        return PaneSize.stored(in: .standard).columns(inWindow: Int(size.ws_col))
    }

    private static func findTmux() -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return (["/opt/homebrew/bin", "/usr/local/bin"] + path.split(separator: ":").map(String.init))
            .map { $0 + "/tmux" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(_ look: Look) -> Never {
        let ring = SampleRing(capacity: 1 << 16)
        let tap = GatedTap(ring: ring)
        let terminal = Terminal()
        let rows = PaneSize.stored(in: .standard).rows
        let analyzer = Analyzer()
        var samples = [Float](repeating: 0, count: Analyzer.fftSize)
        var settled = false
        var tick = 0
        let sections = Sections()
        let music = MusicController()
        var input = PaneInput()
        terminal.write(PaneInput.enableMouse)
        var nextRefresh = Date()
        var lastSize = terminal.size()
        var lastPanel: [UInt8] = []
        var lastBrowser: [UInt8] = []

        // tmux closes the pane with SIGHUP when the window goes.
        for number in [SIGINT, SIGTERM, SIGHUP] { signal(number) { _ in stopping = true } }
        watchKeys()

        while !stopping {
            tick += 1
            if tick % (Int(framesPerSecond) / tapChecksPerSecond) == 0 { tap.update() }

            let size = terminal.size()
            let resized = size != lastSize
            if resized {
                terminal.write("\u{1B}[2J")
                lastSize = size
                lastPanel = []
                lastBrowser = []
            }
            let waveRows = min(rows, max(size.rows - 1, 1))
            let wasOpen = music.isOpen

            var redrawPanel = false
            for event in input.feed(pendingKeys) {
                switch event {
                case .tab:
                    sections.cycle()  // sent by the tmux Option-Tab binding
                    redrawPanel = true
                case .click(let column, let row):
                    // The waveform (and its separator) opens the playlist browser in its place.
                    if row <= waveRows + 1 {
                        if !music.isOpen { music.open() } else if row <= waveRows { music.click(row: row) }
                    } else {
                        sections.click(column: column, row: row)
                        redrawPanel = true
                    }
                case .scroll(let delta, let row):
                    if music.isOpen, row <= waveRows { music.scroll(delta) }
                }
            }
            pendingKeys.removeAll()

            ring.readLatest(into: &samples)
            let levels = analyzer.bands(samples: samples, count: size.cols, sampleRate: tap.sampleRate)
            let quiet = (levels.max() ?? 0) < settledLevel
            if music.isOpen {
                var browser = music.render(width: size.cols, rows: waveRows, palette: look.palette)
                browser += Array("\u{1B}[\(waveRows + 1);1H\u{1B}[0m\u{1B}[2m\(String(repeating: "─", count: size.cols))\u{1B}[0m".utf8)
                if browser != lastBrowser {
                    terminal.write(browser)
                    lastBrowser = browser
                }
            } else if !(quiet && settled) || resized || wasOpen {
                lastBrowser = []
                var canvas = Canvas(cols: size.cols, rows: waveRows)
                canvas.drawBars(levels)
                terminal.write(Renderer.frame(canvas, status: String(repeating: "─", count: size.cols),
                                              palette: look.palette))
            }

            if Date() >= nextRefresh {
                sections.refresh()
                nextRefresh = Date().addingTimeInterval(1)
                redrawPanel = true
            }
            if redrawPanel || resized {
                let panel = sections.render(width: size.cols, firstRow: waveRows + 2, lastRow: size.rows,
                                            palette: look.palette)
                if panel != lastPanel {
                    terminal.write(panel)
                    lastPanel = panel
                }
            }
            settled = quiet
            // Sleeps on the main run loop so Core Location and network replies
            // arrive, and wakes early for a key press.
            let interval = tap.isRunning || !settled ? 1 / Double(framesPerSecond) : idleSeconds
            CFRunLoopRunInMode(.defaultMode, interval, true)
        }
        tap.stop()
        terminal.write(PaneInput.disableMouse)
        terminal.restore()
        exit(0)
    }

    /// Collects key presses on the main queue, waking the run loop.
    private static func watchKeys() {
        FileHandle.standardInput.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { pendingKeys += data }
        }
    }
}

private nonisolated(unsafe) var stopping = false
private nonisolated(unsafe) var pendingKeys: [UInt8] = []
