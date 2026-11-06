import Foundation
import WaveCore

enum View: String { case bars, scope }

let usage = """
soundcrest: live waveform of whatever your Mac is playing.

usage: soundcrest [mode] [--color COLOR] [--backdrop BACKDROP] [--scope]
  (no mode)          desktop background plus the terminal view
  --terminal         terminal view only
  --wallpaper        desktop background only
  --toggle           turn the desktop background on or off
  --autostart on|off start the desktop background at login, or stop doing so
  --pane on|off      open new Terminal windows with a small waveform pane
  --pane-size CxR    pane size in columns and rows, default 48x12
  --probe SECONDS    print input levels instead of drawing, then exit
  --help             show this help

  --color COLOR      \(Palette.presets.keys.sorted().joined(separator: ", ")),
                     a hex colour (ff0000) or two (ff0000,0000ff: centre,edge)
  --backdrop KIND    solid, translucent or transparent (shows your wallpaper)
  --scope            start the terminal in oscilloscope view

--color and --backdrop are remembered for next time.
terminal keys: m switch view, q quit
background: stays on after the terminal closes; \(HotKey.title) or the menu bar
icon turns it off from anywhere
"""

guard let options = Options.parse(Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
if options.mode == .help {
    print(usage)
    exit(0)
}

let look = Look.resolve(options, store: .standard)

/// Starts the background, restarting it if the caller asked for a new look.
func showBackground() {
    if Wallpaper.isRunning {
        guard options.color != nil || options.backdrop != nil else { return }
        Wallpaper.stop()
    }
    Wallpaper.launch(look)
}

switch options.mode {
case .wallpaperRun:
    MainActor.assumeIsolated { Wallpaper.run(look) }
case .wallpaper:
    showBackground()
    print("soundcrest: background on. \(HotKey.title) turns it off.")
    exit(0)
case .toggle:
    if Wallpaper.isRunning {
        Wallpaper.stop()
        print("soundcrest: background off.")
    } else {
        Wallpaper.launch(look)
        print("soundcrest: background on. \(HotKey.title) turns it off.")
    }
    exit(0)
case .autostart(let enabled):
    do {
        if enabled {
            guard let path = Bundle.main.executablePath else { exit(1) }
            try LoginItem.install(executable: LoginItem.stablePath(path))
            print("soundcrest: background will start at login.")
        } else {
            try LoginItem.remove()
            print("soundcrest: background will no longer start at login.")
        }
    } catch {
        FileHandle.standardError.write(Data("soundcrest: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    exit(0)
case .pane(let enabled):
    do {
        if enabled {
            guard let path = Bundle.main.executablePath else { exit(1) }
            try ShellHook.install(executable: LoginItem.stablePath(path))
            print("soundcrest: new Terminal windows will open with the pane.")
        } else {
            try ShellHook.remove()
            print("soundcrest: new Terminal windows will open without the pane.")
        }
    } catch {
        FileHandle.standardError.write(Data("soundcrest: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    exit(0)
case .paneSize(let size):
    size.save(to: .standard)
    print("soundcrest: new panes will be \(size.cols)x\(size.rows).")
    exit(0)
case .paneShell:
    Pane.openShell()
case .paneRun:
    Pane.run(look)
case .both:
    showBackground()
default:
    break
}

var view = options.scope ? View.scope : .bars

let ring = SampleRing(capacity: 1 << 16)
let tap = SystemAudioTap(ring: ring)
do {
    try tap.start()
} catch {
    FileHandle.standardError.write(Data("soundcrest: \(error.localizedDescription)\n".utf8))
    exit(1)
}

var samples = [Float](repeating: 0, count: Analyzer.fftSize)

if case .probe(let probeSeconds) = options.mode {
    let deadline = Date().addingTimeInterval(probeSeconds)
    while Date() < deadline {
        usleep(250_000)
        ring.readLatest(into: &samples)
        let peak = samples.lazy.map { abs($0) }.max() ?? 0
        print(String(format: "rate=%.0f frames=%d peak=%.5f", tap.sampleRate, ring.framesWritten, peak))
    }
    tap.stop()
    exit(0)
}

let terminal = Terminal()
let frameMicros: UInt32 = 16_000
let framesPerSecond = 1_000_000 / Int(frameMicros)
let hintAfterFrames = 5 * framesPerSecond

// Quit via a flag so the terminal is always restored on the main thread.
nonisolated(unsafe) var running = true
signal(SIGINT) { _ in running = false }
signal(SIGTERM) { _ in running = false }

let analyzer = Analyzer()
var silentFrames = 0
var frameNumber = 0

while running {
    while let key = terminal.readKey() {
        switch key {
        case UInt8(ascii: "q"), 3, 27: running = false
        case UInt8(ascii: "m"): view = view == .bars ? .scope : .bars
        default: break
        }
    }

    // Follow the default output when it changes, e.g. plugging in headphones.
    frameNumber += 1
    if frameNumber % framesPerSecond == 0,
       let current = try? defaultOutputDevice(), current != tap.outputDevice {
        tap.stop()
        try? tap.start()
    }

    ring.readLatest(into: &samples)
    silentFrames = samples.contains { $0 != 0 } ? 0 : silentFrames + 1

    let size = terminal.size()
    var canvas = Canvas(cols: size.cols, rows: max(size.rows - 1, 1))
    let levels = analyzer.bands(samples: samples, count: max(size.cols / 2, 1), sampleRate: tap.sampleRate)
    switch view {
    case .bars: canvas.drawBars(levels)
    case .scope: canvas.drawScope(samples)
    }

    var status = "soundcrest · \(view.rawValue) · m view · q quit"
    if silentFrames > hintAfterFrames {
        status += " · no signal: if audio is playing, allow your terminal under "
            + "System Settings > Privacy & Security > System Audio Recording"
    }
    terminal.write(Renderer.frame(canvas, status: status, palette: look.palette))
    usleep(frameMicros)
}

tap.stop()
terminal.restore()
if options.mode == .both {
    print("soundcrest: background still on. \(HotKey.title) or `soundcrest --toggle` turns it off.")
}
