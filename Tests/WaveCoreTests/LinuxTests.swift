import Foundation
import Testing
@testable import WaveCore

@Test func linuxShellHookSkipsSSHEditorsAndConsoles() {
    let block = ShellHook.adding(to: "", executable: "/x", flavor: .linuxDesktop)
    for guardText in ["$- == *i*", "-t 0", "-t 1", "-z \"$TMUX\"", "-z \"$SOUNDCREST_NO_PANE\"",
                      "-z \"$SSH_CONNECTION\"", "${DISPLAY:-$WAYLAND_DISPLAY}", "!= vscode", "-x '/x'"] {
        #expect(block.contains(guardText))
    }
    #expect(!block.contains("Apple_Terminal"))
    #expect(block.contains("exec '/x' --pane-shell"))
    #expect(ShellHook.removing(from: "a=1\n" + block) == "a=1\n")
}

@Test func linuxShellHookIsValidBashAndZsh() throws {
    let block = ShellHook.adding(to: "", executable: "/nonexistent/soundcrest", flavor: .linuxDesktop)
    for shell in ["/bin/bash", "/bin/zsh"] where FileManager.default.isExecutableFile(atPath: shell) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-n", "-c", block]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(shell) rejected the hook")
    }
}

@Test func sha256MatchesKnownVectors() {
    let hex = { (bytes: [UInt8]) in bytes.map { String(format: "%02x", $0) }.joined() }
    #expect(hex(SHA256Digest.hash([])) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(hex(SHA256Digest.hash(Array("abc".utf8))) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    let twoBlocks = Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
    #expect(hex(SHA256Digest.hash(twoBlocks)) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    #expect(hex(SHA256Digest.hash([UInt8](repeating: 0x61, count: 1000)))
        == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
}

@Test func linuxSystemParsersReadProcFiles() {
    #expect(LinuxSystem.osName(osRelease: "NAME=\"Ubuntu\"\nPRETTY_NAME=\"Ubuntu 24.04.1 LTS\"\nID=ubuntu\n")
        == "Ubuntu 24.04.1 LTS")
    #expect(LinuxSystem.osName(osRelease: "NAME=Arch Linux\n") == "Arch Linux")

    let memory = LinuxSystem.memory(meminfo: "MemTotal:       16000000 kB\nMemFree:  1000 kB\nMemAvailable:    4000000 kB\n")
    #expect(memory?.total == 16_000_000 * 1024)
    #expect(memory?.used == 12_000_000 * 1024)
    #expect(LinuxSystem.memory(meminfo: "nothing") == nil)

    #expect(LinuxSystem.cpuModel(cpuinfo: "processor\t: 0\nmodel name\t: AMD Ryzen 7  7840U w/ Radeon\n")
        == "AMD Ryzen 7 7840U w/ Radeon")
    #expect(LinuxSystem.cpuModel(cpuinfo: "processor\t: 0\nModel\t\t: Raspberry Pi 5 Model B Rev 1.0\n")
        == "Raspberry Pi 5 Model B Rev 1.0")
    #expect(LinuxSystem.cpuModel(cpuinfo: "processor\t: 0\nBogoMIPS\t: 48.00\n") == nil)

    #expect(LinuxSystem.uptime(procUptime: "350735.47 234388.90\n") == 350_735)
    let status = """
    Package: a
    Status: install ok installed

    Package: b
    Status: deinstall ok config-files

    Package: c
    Status: install ok installed
    """
    #expect(LinuxSystem.dpkgCount(status: status) == 2)
    #expect(LinuxSystem.battery(capacity: "84\n", status: "Charging\n") == "84% charging")
    #expect(LinuxSystem.battery(capacity: "100", status: "Full") == "100% plugged in")
    #expect(LinuxSystem.battery(capacity: "40", status: "Discharging") == "40%")
    #expect(LinuxSystem.battery(capacity: "", status: "Full") == nil)
}

@Test func spotifyOnLinuxPlaysThroughMPRIS() {
    let arguments = SpotifyAPI.mprisOpenArguments(track: Track(id: "spotify:track:1", title: "", artist: ""))
    #expect(arguments.contains("--dest=org.mpris.MediaPlayer2.spotify"))
    #expect(arguments.last == "string:spotify:track:1")
}

@Test func analyzerFindsAToneWithThePortableFFT() {
    let analyzer = Analyzer()
    // 1 kHz at 48 kHz, half scale: the band holding 1 kHz should be the loudest.
    let samples = (0..<Analyzer.fftSize).map { 0.5 * sin(2 * Float.pi * 1000 * Float($0) / 48_000) }
    var levels: [Float] = []
    for _ in 0..<20 { levels = analyzer.bands(samples: samples, count: 32, sampleRate: 48_000) }
    let loudest = levels.indices.max { levels[$0] < levels[$1] }!
    let ratio: Float = 16_000 / 40
    let low = 40 * pow(ratio, Float(loudest) / 32), high = 40 * pow(ratio, Float(loudest + 1) / 32)
    #expect(low <= 1000 && 1000 <= high * 1.2)
}
