import Darwin
import Foundation
import WaveCore

/// Runs inside the new window: `--pane-shell` lays it out, `--pane-run` draws.
enum Pane {
    private static let framesPerSecond: UInt32 = 30
    private static let tapChecksPerSecond = 2
    private static let idleMicros: UInt32 = 250_000
    private static let settledLevel: Float = 0.002
    private static let bands = 32

    /// Never leaves the window without a shell, whatever goes wrong.
    static func openShell() -> Never {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let tmux = findTmux(), let path = Bundle.main.executablePath, windowFits() {
            let arguments = PaneLayout.tmuxArguments(
                tmux: tmux, shell: shell, executable: LoginItem.stablePath(path))
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

    private static func windowFits() -> Bool {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 else { return false }
        return PaneLayout.fits(cols: Int(size.ws_col))
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
        let analyzer = Analyzer()
        var samples = [Float](repeating: 0, count: Analyzer.fftSize)
        var settled = false
        var tick = 0

        // tmux closes the pane with SIGHUP when the window goes.
        for number in [SIGINT, SIGTERM, SIGHUP] { signal(number) { _ in stopping = true } }

        while !stopping {
            tick += 1
            if tick % (Int(framesPerSecond) / tapChecksPerSecond) == 0 { tap.update() }

            ring.readLatest(into: &samples)
            let size = terminal.size()
            let cols = min(size.cols, PaneLayout.width)
            let levels = analyzer.bands(samples: samples, count: bands, sampleRate: tap.sampleRate)
            let quiet = (levels.max() ?? 0) < settledLevel
            if !(quiet && settled) {
                var canvas = Canvas(cols: cols, rows: min(PaneLayout.height, max(size.rows - 1, 1)))
                canvas.drawBars(levels)
                terminal.write(Renderer.frame(canvas, status: String(repeating: "─", count: cols),
                                              palette: look.palette))
            }
            settled = quiet
            usleep(tap.isRunning || !settled ? 1_000_000 / framesPerSecond : idleMicros)
        }
        tap.stop()
        terminal.restore()
        exit(0)
    }
}

private nonisolated(unsafe) var stopping = false
