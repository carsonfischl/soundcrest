import Foundation
import WaveCore

enum View: String { case bars, scope }

#if os(macOS)
let platformModes = """
  (no mode)          desktop background plus the terminal view
  --terminal         terminal view only
  --wallpaper        desktop background only
  --toggle           turn the desktop background on or off
  --autostart on|off start the desktop background at login, or stop doing so
  --pane on|off      open new Terminal windows with a small waveform pane
"""
let lookUsage = "[--backdrop BACKDROP] "
let lookOptions = "  --backdrop KIND    solid, translucent or transparent (shows your wallpaper)\n"
let platformNotes = """
--color and --backdrop are remembered for next time.
terminal keys: m switch view, q quit
pane: click the waveform to play from Spotify or YouTube playlists; click the
views under it, or press Option-Tab (needs Terminal's "Use Option as Meta key"),
to switch between info, weather and news
background: stays on after the terminal closes; \(HotKey.title) or the menu bar
icon turns it off from anywhere
"""
let noSignalHint = "if audio is playing, allow your terminal under "
    + "System Settings > Privacy & Security > System Audio Recording"
#else
let platformModes = """
  (no mode), --terminal  the waveform in this terminal
  --pane on|off      open new terminal windows with a small waveform pane
"""
let lookUsage = ""
let lookOptions = ""
let platformNotes = """
--color is remembered for next time.
terminal keys: m switch view, q quit
pane: click the waveform to play from Spotify or YouTube playlists; click the
views under it to switch between info, weather and news
audio: recorded from the default output with parec (PulseAudio or PipeWire)
"""
let noSignalHint = "is parec installed, and is PulseAudio or PipeWire running?"
#endif

let usage = """
soundcrest: live waveform of whatever your computer is playing.

usage: soundcrest [mode] [--color COLOR] \(lookUsage)[--scope]
\(platformModes)
  --pane-size CxR    pane size in columns and rows, default 48x12
  --pane-info on|off, --pane-weather on|off, --pane-news on|off
                     show or hide each view under the pane's waveform
  --weather-location CITY|auto
                     weather for CITY instead of your location
  --news-sources LIST
                     comma-separated from \(NewsSource.presets.map(\.id).joined(separator: ", "))
                     (default \(NewsSource.defaults.map(\.id).joined(separator: ",")))
  --spotify-client-id ID
                     let the pane browse your Spotify playlists (see README)
  --youtube-client ID SECRET
                     let the pane browse your YouTube playlists (see README)
  --music-sign-out spotify|youtube
                     forget that service's sign-in
  --probe SECONDS    print input levels instead of drawing, then exit
  --help             show this help

  --color COLOR      \(Palette.presets.keys.sorted().joined(separator: ", ")),
                     a hex colour (ff0000) or two (ff0000,0000ff: centre,edge)
\(lookOptions)  --scope            start the terminal in oscilloscope view

\(platformNotes)
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

#if os(macOS)
/// Starts the background, restarting it if the caller asked for a new look.
func showBackground() {
    if Wallpaper.isRunning {
        guard options.color != nil || options.backdrop != nil else { return }
        Wallpaper.stop()
    }
    Wallpaper.launch(look)
}
#endif

switch options.mode {
#if os(macOS)
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
case .locate:
    MainActor.assumeIsolated { LocationHelper.run() }
case .both:
    showBackground()
#else
case .wallpaper, .wallpaperRun, .toggle, .autostart, .locate:
    FileHandle.standardError.write(Data("soundcrest: the desktop background is only on macOS.\n".utf8))
    exit(2)
#endif
case .pane(let enabled):
    do {
        if enabled {
            guard let path = Bundle.main.executablePath else { exit(1) }
            try ShellHook.install(executable: LoginItem.stablePath(path))
            print("soundcrest: new terminal windows will open with the pane (\(ShellHook.file.path)).")
        } else {
            try ShellHook.remove()
            print("soundcrest: new terminal windows will open without the pane.")
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
case .paneSection(let section, let enabled):
    PaneSettings.setEnabled(section, enabled, in: .standard)
    print("soundcrest: \(section.title) \(enabled ? "shown" : "hidden") under the pane's waveform.")
    exit(0)
case .weatherLocation(let place):
    PaneSettings.setWeatherLocation(place, in: .standard)
    print("soundcrest: weather for \(place ?? "your current location").")
    exit(0)
case .newsSources(let sources):
    PaneSettings.setNewsSources(sources, in: .standard)
    print("soundcrest: headlines from \(sources.map(\.name).joined(separator: ", ")).")
    exit(0)
case .musicCredentials(let service, let credentials):
    credentials.save(service, in: .standard)
    TokenStore.save(nil, for: service)
    print("soundcrest: \(service.title) is set up. Click the pane's waveform to sign in.")
    exit(0)
case .musicSignOut(let service):
    TokenStore.save(nil, for: service)
    print("soundcrest: signed out of \(service.title).")
    exit(0)
case .paneShell:
    Pane.openShell()
case .paneRun:
    Pane.run(look)
default:
    break
}

var view = options.scope ? View.scope : .bars

let ring = SampleRing(capacity: 1 << 16)
#if os(macOS)
let tap = SystemAudioTap(ring: ring)
do {
    try tap.start()
} catch {
    FileHandle.standardError.write(Data("soundcrest: \(error.localizedDescription)\n".utf8))
    exit(1)
}
#else
let tap = LinuxCapture(ring: ring)
tap.start()
if let failure = tap.failure {
    FileHandle.standardError.write(Data("soundcrest: \(failure)\n".utf8))
    exit(1)
}
#endif

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
    #if os(macOS)
    if frameNumber % framesPerSecond == 0,
       let current = try? defaultOutputDevice(), current != tap.outputDevice {
        tap.stop()
        try? tap.start()
    }
    #else
    // parec follows the default output itself; restart it if it exits.
    if frameNumber % framesPerSecond == 0 { tap.update() }
    #endif

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
        status += " · no signal: " + noSignalHint
    }
    terminal.write(Renderer.frame(canvas, status: status, palette: look.palette))
    usleep(frameMicros)
}

tap.stop()
terminal.restore()
#if os(macOS)
if options.mode == .both {
    print("soundcrest: background still on. \(HotKey.title) or `soundcrest --toggle` turns it off.")
}
#endif
