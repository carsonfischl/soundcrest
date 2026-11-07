#if canImport(Accelerate)
import Accelerate
#endif
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
                      ["--pane"], ["--pane", "maybe"], ["--pane-size"], ["--pane-size", "big"]] {
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
    #expect(Options.parse(["--pane-size", "60x16"])?.mode == .paneSize(PaneSize(cols: 60, rows: 16)))
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
    let block = ShellHook.adding(to: "", executable: "/x", flavor: .terminalApp)
    for guardText in ["-o interactive", "-t 0", "-t 1", "Apple_Terminal", "-z \"$TMUX\"", "-z \"$SOUNDCREST_NO_PANE\"", "-x '/x'"] {
        #expect(block.contains(guardText))
    }
}

@Test func shellQuotingSurvivesSpacesAndApostrophes() {
    #expect(ShellHook.quoted("/a b/it's") == "'/a b/it'\\''s'")
}

@Test func paneDefaultsToDoubleItsOriginalSize() {
    #expect(PaneSize.standard == PaneSize(cols: 48, rows: 12))
}

@Test func paneSizeParsesColumnsByRows() {
    #expect(PaneSize(spec: "60x16") == PaneSize(cols: 60, rows: 16))
}

@Test func paneSizeRejectsUnusableValues() {
    for spec in ["", "60", "x16", "60x", "axb", "11x8", "48x2", "200x8", "48x60"] {
        #expect(PaneSize(spec: spec) == nil)
    }
}

@Test func paneSizeIsRememberedAndFallsBackToStandard() {
    let store = emptyStore()
    #expect(PaneSize.stored(in: store) == .standard)
    PaneSize(cols: 60, rows: 16).save(to: store)
    #expect(PaneSize.stored(in: store) == PaneSize(cols: 60, rows: 16))
}

@Test func paneShrinksToLeaveTheShellRoom() {
    #expect(PaneSize.standard.columns(inWindow: 120) == 48)
    #expect(PaneSize.standard.columns(inWindow: 80) == 40)
}

@Test func paneIsSkippedWhenWindowIsTooNarrow() {
    #expect(PaneSize.standard.columns(inWindow: 52) == 12)
    #expect(PaneSize.standard.columns(inWindow: 51) == nil)
}

private func tmuxWords() -> [String] {
    PaneLayout.tmuxArguments(tmux: "/bin/tmux", shell: "/bin/zsh", executable: "/bin/soundcrest", paneCols: 40)
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
    #expect(Array(words[split...]).prefix(5) == ["split-window", "-d", "-h", "-l", "40"])
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

@Test func fftFindsToneInItsBin() {
    let bin = 100
    let samples = (0..<4096).map { sin(2 * Float.pi * Float(bin * $0) / 4096) }
    let magnitudes = RealFFT(size: 4096).magnitudes(of: samples)
    #expect(magnitudes.count == 2048)
    #expect(magnitudes.indices.max { magnitudes[$0] < magnitudes[$1] } == bin)
}

#if canImport(Accelerate)
/// The auto-gain floor is an absolute level, so the scale has to match vDSP's.
@Test func fftMatchesAccelerateScale() {
    let size = 4096
    let samples = (0..<size).map { i -> Float in
        let t = Float(i) / Float(size)
        return 0.5 * sin(2 * .pi * 37 * t) + 0.25 * cos(2 * .pi * 411 * t) + 0.1 * sin(2 * .pi * 1500.5 * t)
    }

    var real = [Float](repeating: 0, count: size / 2)
    var imag = real
    var expected = real
    let setup = vDSP_create_fftsetup(12, FFTRadix(kFFTRadix2))!
    defer { vDSP_destroy_fftsetup(setup) }
    real.withUnsafeMutableBufferPointer { realPointer in
        imag.withUnsafeMutableBufferPointer { imagPointer in
            var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
            samples.withUnsafeBytes {
                vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(size / 2))
            }
            vDSP_fft_zrip(setup, &split, 1, 12, FFTDirection(kFFTDirection_Forward))
            split.imagp[0] = 0
            vDSP_zvabs(&split, 1, &expected, 1, vDSP_Length(size / 2))
        }
    }

    let actual = RealFFT(size: size).magnitudes(of: samples)
    for bin in expected.indices {
        #expect(abs(actual[bin] - expected[bin]) <= max(expected[bin] * 0.001, 0.01))
    }
}
#endif

private func bytes(_ samples: [Float]) -> Data {
    samples.withUnsafeBufferPointer { Data(buffer: $0) }
}

@Test func pcmStreamDecodesFloats() {
    var stream = PCMStream()
    #expect(stream.append(bytes([0.5, -0.25])) == [0.5, -0.25])
}

@Test func pcmStreamKeepsPartialFloatForNextRead() {
    var stream = PCMStream()
    let data = bytes([0.5, -0.25])
    #expect(stream.append(data.prefix(6)) == [0.5])
    #expect(stream.append(data.dropFirst(6)) == [-0.25])
}

@Test func pcmStreamHandlesSliceWithOffsetIndices() {
    var stream = PCMStream()
    #expect(stream.append(bytes([1, 2, 3]).dropFirst(4)) == [2, 3])
}

@Test func recorderCapturesTheDefaultMonitorAsStereoFloat() {
    #expect(LinuxRecorder.arguments == [
        "--raw", "--device=@DEFAULT_MONITOR@", "--format=float32le",
        "--rate=48000", "--channels=2", "--latency-msec=20",
    ])
}
