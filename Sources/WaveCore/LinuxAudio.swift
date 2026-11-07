import Foundation

/// How soundcrest records system audio on Linux: `parec` (from PulseAudio's
/// tools, also served by PipeWire's pulse layer) reading the default output's
/// monitor, as raw interleaved float32.
public enum LinuxRecorder {
    public static let tool = "parec"
    public static let sampleRate: Float = 48_000
    public static let channels = 2

    public static let arguments = [
        "--raw", "--device=@DEFAULT_MONITOR@", "--format=float32le",
        "--rate=\(Int(sampleRate))", "--channels=\(channels)", "--latency-msec=20",
    ]
}

/// Little-endian float32 samples from a byte stream that may split a sample
/// across reads.
public struct PCMStream {
    private var leftover: [UInt8] = []

    public init() {}

    public mutating func append(_ data: Data) -> [Float] {
        let bytes = leftover + data  // copies, so slice indices don't matter
        let whole = bytes.count / 4 * 4
        leftover = Array(bytes[whole...])
        var samples = [Float](repeating: 0, count: whole / 4)
        for index in samples.indices {
            let offset = index * 4
            let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            samples[index] = Float(bitPattern: bits)
        }
        return samples
    }
}
