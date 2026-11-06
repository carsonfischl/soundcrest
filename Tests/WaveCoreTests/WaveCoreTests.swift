import Foundation
import Testing
@testable import WaveCore

private let rate: Float = 48_000

private func sine(hz: Float, amplitude: Float = 0.5) -> [Float] {
    (0..<Analyzer.fftSize).map { amplitude * sin(2 * .pi * hz * Float($0) / rate) }
}

private func settledBands(_ samples: [Float], count: Int = 64) -> [Float] {
    let analyzer = Analyzer()
    var levels: [Float] = []
    for _ in 0..<30 { levels = analyzer.bands(samples: samples, count: count, sampleRate: rate) }
    return levels
}

@Test func silenceStaysFlat() {
    let levels = settledBands([Float](repeating: 0, count: Analyzer.fftSize))
    #expect(levels.allSatisfy { $0 == 0 })
}

@Test func toneLandsInMatchingBand() {
    func loudest(_ hz: Float) -> Int {
        let levels = settledBands(sine(hz: hz))
        return levels.indices.max { levels[$0] < levels[$1] }!
    }
    let expected = { (hz: Float) in Int(64 * log(hz / 40) / log(16_000 / 40)) }
    #expect(abs(loudest(200) - expected(200)) <= 2)
    #expect(abs(loudest(5_000) - expected(5_000)) <= 2)
}

@Test func fullScaleToneReachesTop() {
    #expect((settledBands(sine(hz: 1_000)).max() ?? 0) > 0.9)
}

@Test func decaysAfterSoundStops() {
    let analyzer = Analyzer()
    var levels: [Float] = []
    for _ in 0..<30 { levels = analyzer.bands(samples: sine(hz: 1_000), count: 64, sampleRate: rate) }
    let loud = levels.max()!
    let silence = [Float](repeating: 0, count: Analyzer.fftSize)
    for _ in 0..<60 { levels = analyzer.bands(samples: silence, count: 64, sampleRate: rate) }
    #expect(levels.max()! < loud * 0.05)
}

@Test func ringReturnsNewestMonoSamplesAcrossWrap() {
    let ring = SampleRing(capacity: 8)
    let stereo: [Float] = (0..<12).flatMap { [Float($0), Float($0) + 2] }
    ring.write(stereo, frames: 12, channels: 2)
    var out = [Float](repeating: 0, count: 4)
    ring.readLatest(into: &out)
    #expect(out == [9, 10, 11, 12])
}

@Test func silentBarsDrawOnlyCentreLine() {
    var canvas = Canvas(cols: 4, rows: 2)
    canvas.drawBars([0, 0])
    #expect((0..<4).allSatisfy { canvas.cell(col: $0, row: 0) == 0x40 | 0x80 })
    #expect((0..<4).allSatisfy { canvas.cell(col: $0, row: 1) == 0 })
}

@Test func barsFillHeightAtFullLevel() {
    var canvas = Canvas(cols: 2, rows: 2)
    canvas.drawBars([1, 1])
    #expect(canvas.cell(col: 0, row: 0) == 0xFF)
}

@Test func vlineClipsToCanvas() {
    var canvas = Canvas(cols: 1, rows: 1)
    canvas.vline(x: 0, y0: -5, y1: 50)
    canvas.vline(x: 9, y0: 0, y1: 3)
    #expect(canvas.cell(col: 0, row: 0) == 0x01 | 0x02 | 0x04 | 0x40)
}

@Test func brailleEncodesAsUTF8() {
    var bytes: [UInt8] = []
    Renderer.appendBraille(0xFF, to: &bytes)
    #expect(String(decoding: bytes, as: UTF8.self) == "\u{28FF}")
}

@Test func silhouetteIsSymmetricWithLowsAtCentre() {
    let heights = Silhouette.heights(levels: [1, 0.5, 0, 0], columns: 101)
    #expect(heights.count == 101)
    #expect(heights[50] > heights[75])
    #expect(heights[75] > heights[100])
    #expect((0..<101).allSatisfy { abs(heights[$0] - heights[100 - $0]) < 1e-4 })
}

@Test func silhouetteOfSilenceIsFlat() {
    #expect(Silhouette.heights(levels: [0, 0, 0], columns: 16).allSatisfy { $0 == 0 })
}

@Test func silhouetteHandlesSingleBand() {
    #expect(Silhouette.heights(levels: [0.5], columns: 4) == [0.5, 0.5, 0.5, 0.5])
}

@Test func ringClearDropsOldSamples() {
    let ring = SampleRing(capacity: 16)
    let loud = [Float](repeating: 1, count: 16)
    ring.write(loud, frames: 16, channels: 1)
    ring.clear()
    var out = [Float](repeating: 1, count: 8)
    ring.readLatest(into: &out)
    #expect(out.allSatisfy { $0 == 0 })
}

private func gateOpen(hold: Double = 5, at steps: [(active: Bool, now: Double)]) -> [Bool] {
    var gate = TapGate(hold: hold)
    return steps.map { gate.update(outputActive: $0.active, now: $0.now) }
}

@Test func gateStaysClosedWithoutOutput() {
    #expect(gateOpen(at: [(false, 0), (false, 100)]) == [false, false])
}

@Test func gateOpensAsSoonAsOutputStarts() {
    #expect(gateOpen(at: [(false, 0), (true, 1)]) == [false, true])
}

@Test func gateHoldsThroughShortGaps() {
    let open = gateOpen(at: [(true, 10), (false, 14.9), (true, 15), (false, 19.9)])
    #expect(open == [true, true, true, true])
}

@Test func gateClosesAfterHoldExpires() {
    #expect(gateOpen(at: [(true, 10), (false, 15)]) == [true, false])
}

@Test func paletteResolvesPresetNames() {
    #expect(Palette(spec: "ember") == Palette.presets["ember"])
    #expect(Palette(spec: "EMBER") == Palette.presets["ember"])
}

@Test func paletteParsesOneHexAsSolidColor() {
    let red = RGB(r: 255, g: 0, b: 0)
    #expect(Palette(spec: "ff0000") == Palette(centre: red, edge: red))
    #expect(Palette(spec: "#ff0000") == Palette(centre: red, edge: red))
}

@Test func paletteParsesTwoHexAsCentreThenEdge() {
    let palette = Palette(spec: "ff0000,0000ff")
    #expect(palette?.centre == RGB(r: 255, g: 0, b: 0))
    #expect(palette?.edge == RGB(r: 0, g: 0, b: 255))
}

@Test func paletteRejectsBadSpecs() {
    for spec in ["", "nope", "ff00", "gg0000", "ff0000,", "ff0000,00ff00,0000ff"] {
        #expect(Palette(spec: spec) == nil)
    }
}

@Test func rendererDrawsChosenPalette() {
    let green = RGB(r: 0, g: 255, b: 0)
    let canvas = Canvas(cols: 2, rows: 3)
    let bytes = Renderer.frame(canvas, status: "", palette: Palette(centre: green, edge: green))
    #expect(String(decoding: bytes, as: UTF8.self).contains("\u{1B}[38;2;0;255;0m"))
}

@Test func backdropAlphaRunsFromOpaqueToClear() {
    #expect(Backdrop.solid.alpha == 1)
    #expect(Backdrop.translucent.alpha > 0 && Backdrop.translucent.alpha < 1)
    #expect(Backdrop.transparent.alpha == 0)
}

@Test func optionsDefaultToBackgroundPlusTerminal() {
    #expect(Options.parse([])?.mode == .both)
}

@Test func optionsSelectModes() {
    #expect(Options.parse(["--terminal"])?.mode == .terminal)
    #expect(Options.parse(["--wallpaper"])?.mode == .wallpaper)
    #expect(Options.parse(["--toggle"])?.mode == .toggle)
    #expect(Options.parse(["--probe", "2"])?.mode == .probe(2))
    #expect(Options.parse(["--help"])?.mode == .help)
}

@Test func optionsKeepLookFlagsInAnyOrder() {
    let options = Options.parse(["--color", "ocean", "--wallpaper", "--backdrop", "translucent"])
    #expect(options?.mode == .wallpaper)
    #expect(options?.color == "ocean")
    #expect(options?.backdrop == .translucent)
}

@Test func optionsRejectBadInput() {
    for arguments in [["--nope"], ["--color"], ["--color", "nope"], ["--backdrop", "nope"], ["--probe", "x"],
                      ["--autostart"], ["--autostart", "maybe"],
                      ["--pane"], ["--pane", "maybe"]] {
        #expect(Options.parse(arguments) == nil)
    }
}

private func emptyStore() -> UserDefaults {
    UserDefaults(suiteName: "soundcrest.tests.\(UUID().uuidString)")!
}

@Test func lookUsesDefaultsWhenNothingChosen() {
    let look = Look.resolve(Options(), store: emptyStore())
    #expect(look.color == Palette.defaultName)
    #expect(look.backdrop == .solid)
}

@Test func lookAppliesFlagsWithoutAStore() {
    let options = Options.parse(["--color", "ember", "--backdrop", "transparent"])!
    let look = Look.resolve(options, store: nil)
    #expect(look.color == "ember")
    #expect(look.backdrop == .transparent)
}

@Test func lookRemembersFlagsForLaterRuns() {
    let store = emptyStore()
    _ = Look.resolve(Options.parse(["--color", "ember", "--backdrop", "translucent"])!, store: store)
    let later = Look.resolve(Options(), store: store)
    #expect(later.color == "ember")
    #expect(later.backdrop == .translucent)
}

@Test func lookPrefersNewFlagOverRemembered() {
    let store = emptyStore()
    _ = Look.resolve(Options.parse(["--color", "ember"])!, store: store)
    #expect(Look.resolve(Options.parse(["--color", "ocean"])!, store: store).color == "ocean")
}

@Test func optionsSelectAutostart() {
    #expect(Options.parse(["--autostart", "on"])?.mode == .autostart(true))
    #expect(Options.parse(["--autostart", "off"])?.mode == .autostart(false))
}

private func temporaryAgentsDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("soundcrest-tests-\(UUID().uuidString)")
        .appendingPathComponent("LaunchAgents")
}

private func installedJob(in directory: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: LoginItem.file(in: directory))
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(plist as? [String: Any])
}

@Test func loginItemStartsBackgroundOnceAtLogin() throws {
    let directory = temporaryAgentsDirectory()
    try LoginItem.install(executable: "/usr/local/bin/soundcrest", in: directory)

    let job = try installedJob(in: directory)
    #expect(job["Label"] as? String == "local.soundcrest")
    #expect(job["ProgramArguments"] as? [String] == ["/usr/local/bin/soundcrest", "--wallpaper-run"])
    #expect(job["RunAtLoad"] as? Bool == true)
}

@Test func loginItemDoesNotRestartAfterBackgroundIsTurnedOff() throws {
    let directory = temporaryAgentsDirectory()
    try LoginItem.install(executable: "/usr/local/bin/soundcrest", in: directory)
    #expect(try installedJob(in: directory)["KeepAlive"] == nil)
}

@Test func loginItemInstallReplacesEarlierPath() throws {
    let directory = temporaryAgentsDirectory()
    try LoginItem.install(executable: "/old/soundcrest", in: directory)
    try LoginItem.install(executable: "/new/soundcrest", in: directory)
    #expect(try installedJob(in: directory)["ProgramArguments"] as? [String] == ["/new/soundcrest", "--wallpaper-run"])
}

@Test func loginItemRemoveDeletesFile() throws {
    let directory = temporaryAgentsDirectory()
    try LoginItem.install(executable: "/usr/local/bin/soundcrest", in: directory)
    try LoginItem.remove(in: directory)
    #expect(!FileManager.default.fileExists(atPath: LoginItem.file(in: directory).path))
}

@Test func loginItemRemoveIsFineWhenNothingInstalled() throws {
    try LoginItem.remove(in: temporaryAgentsDirectory())
}

@Test func loginItemSurvivesHomebrewUpgrades() {
    #expect(LoginItem.stablePath("/opt/homebrew/Cellar/soundcrest/0.1.0/bin/soundcrest")
        == "/opt/homebrew/bin/soundcrest")
    #expect(LoginItem.stablePath("/Users/me/.local/bin/soundcrest") == "/Users/me/.local/bin/soundcrest")
}

@Test func optionsSelectPane() {
    #expect(Options.parse(["--pane", "on"])?.mode == .pane(true))
    #expect(Options.parse(["--pane", "off"])?.mode == .pane(false))
    #expect(Options.parse(["--pane-shell"])?.mode == .paneShell)
    #expect(Options.parse(["--pane-run"])?.mode == .paneRun)
}

@Test func shellHookKeepsExistingConfigAndRemovesCleanly() {
    let original = "export A=1\n\nalias b=c\n"
    let added = ShellHook.adding(to: original, executable: "/usr/local/bin/soundcrest")
    #expect(added.hasPrefix(original))
    #expect(added.contains("exec '/usr/local/bin/soundcrest' --pane-shell"))
    #expect(ShellHook.removing(from: added) == original)
}

@Test func shellHookRestoresFileWithoutTrailingNewline() {
    let original = "export A=1"
    #expect(ShellHook.removing(from: ShellHook.adding(to: original, executable: "/x")) == original)
}

@Test func shellHookIsNotDuplicatedAndPicksUpNewPath() {
    let once = ShellHook.adding(to: "", executable: "/old/soundcrest")
    let twice = ShellHook.adding(to: once, executable: "/new/soundcrest")
    #expect(twice.components(separatedBy: "--pane-shell").count == 2)
    #expect(twice.contains("/new/soundcrest"))
    #expect(!twice.contains("/old/soundcrest"))
}

@Test func shellHookRemoveLeavesOtherFilesAlone() {
    #expect(ShellHook.removing(from: "export A=1\n") == "export A=1\n")
}

@Test func shellHookRunsOnlyInInteractiveTerminalApp() {
    let block = ShellHook.adding(to: "", executable: "/x")
    for guardText in ["-o interactive", "-t 0", "-t 1", "Apple_Terminal", "-z \"$TMUX\"", "-z \"$SOUNDCREST_NO_PANE\"", "-x '/x'"] {
        #expect(block.contains(guardText))
    }
}

@Test func shellQuotingSurvivesSpacesAndApostrophes() {
    #expect(ShellHook.quoted("/a b/it's") == "'/a b/it'\\''s'")
}

@Test func paneNeedsRoomBesideTheShell() {
    #expect(!PaneLayout.fits(cols: 79))
    #expect(PaneLayout.fits(cols: 80))
}

private func tmuxWords() -> [String] {
    PaneLayout.tmuxArguments(tmux: "/bin/tmux", shell: "/bin/zsh", executable: "/bin/soundcrest")
}

@Test func paneUsesItsOwnHiddenTmuxServer() {
    let words = tmuxWords()
    #expect(Array(words.prefix(4)) == ["-L", "soundcrest", "-f", "/dev/null"])
    #expect(words.contains("status"))
    #expect(words.contains("prefix"))
}

@Test func paneSessionEndsWithItsWindow() {
    let words = tmuxWords()
    #expect(words.contains("destroy-unattached"))
    #expect(words.contains("'/bin/zsh' -l; '/bin/tmux' -L soundcrest kill-session"))
}

@Test func paneOpensRightColumnWithoutTakingFocus() {
    let words = tmuxWords()
    let split = try! #require(words.firstIndex(of: "split-window"))
    #expect(Array(words[split...]).prefix(5) == ["split-window", "-d", "-h", "-l", "24"])
    #expect(words.contains("'/bin/soundcrest' --pane-run"))
}

@Test func listenersDoNotCountAsPlaying() {
    let listening = AudioClient(bundleID: "local.soundcrest", isRunningOutput: true)
    #expect(!AudioClient.anyPlaying([listening, listening]))
}

@Test func otherAppsCountAsPlaying() {
    let idle = AudioClient(bundleID: "com.apple.Music", isRunningOutput: false)
    let chrome = AudioClient(bundleID: "com.google.Chrome.helper", isRunningOutput: true)
    #expect(!AudioClient.anyPlaying([idle]))
    #expect(AudioClient.anyPlaying([idle, chrome]))
}

@Test func unnamedProcessStillCountsAsPlaying() {
    #expect(AudioClient.anyPlaying([AudioClient(bundleID: nil, isRunningOutput: true)]))
}
