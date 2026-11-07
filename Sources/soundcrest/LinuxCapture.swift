#if os(Linux)
import Foundation
import Glibc
import WaveCore

/// Records what the default output plays by running `parec` on its monitor
/// source (PulseAudio, or PipeWire's pulse layer). Same shape as macOS's
/// `GatedTap`, so the pane and terminal view drive either one.
final class LinuxCapture {
    private static let retrySeconds = 3.0

    private let ring: SampleRing
    private var process: Process?
    private var lastStart = -Double.infinity
    private(set) var failure: String?

    var isRunning: Bool { process?.isRunning ?? false }
    var sampleRate: Float { LinuxRecorder.sampleRate }

    init(ring: SampleRing) { self.ring = ring }

    /// Starts recording, or restarts it a few seconds after it stops.
    func update() {
        guard !isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastStart >= Self.retrySeconds else { return }
        lastStart = now
        start()
    }

    func start() {
        guard let tool = Self.find(LinuxRecorder.tool) else {
            failure = "parec not found: install pulseaudio-utils (Debian, Ubuntu, Fedora) or libpulse (Arch)"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = LinuxRecorder.arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            failure = "couldn't start parec: \(error.localizedDescription)"
            return
        }
        failure = nil
        self.process = process

        let ring = self.ring
        let fd = output.fileHandleForReading.fileDescriptor
        let reader = Thread {
            var stream = PCMStream()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            var carry: [Float] = []  // a frame split across reads
            let channels = LinuxRecorder.channels
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count <= 0 { break }
                let samples = carry + stream.append(Data(buffer[..<count]))
                let frames = samples.count / channels
                carry = Array(samples[(frames * channels)...])
                guard frames > 0 else { continue }
                samples.withUnsafeBufferPointer {
                    ring.write($0.baseAddress!, frames: frames, channels: LinuxRecorder.channels)
                }
            }
            ring.clear()
        }
        reader.name = "soundcrest parec reader"
        reader.start()
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private static func find(_ tool: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        return (path.split(separator: ":").map(String.init) + ["/usr/bin", "/bin"])
            .map { $0 + "/" + tool }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
#endif
