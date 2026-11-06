import Accelerate

/// Turns time-domain samples into smoothed, log-spaced band levels in 0...1.
public final class Analyzer {
    public static let fftSize = 4096

    private static let log2n = vDSP_Length(12)
    private static let minHz: Float = 40
    private static let maxHz: Float = 16_000
    private static let rangeDB: Float = 50
    /// Keeps the auto-gain from inflating background noise into a full display.
    private static let referenceFloorDB: Float = -35
    private static let referenceDecayDB: Float = 0.03
    /// Music rolls off with frequency; this tilt keeps treble visible.
    private static let tiltDBPerOctave: Float = 3

    private let setup: FFTSetup
    private let window: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var levels: [Float] = []
    private var referenceDB = Analyzer.referenceFloorDB

    public init() {
        setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: Self.fftSize, isHalfWindow: false)
        real = .init(repeating: 0, count: Self.fftSize / 2)
        imag = real
        magnitudes = real
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// `samples` must hold exactly `fftSize` values.
    public func bands(samples: [Float], count: Int, sampleRate: Float) -> [Float] {
        precondition(samples.count == Self.fftSize)
        computeMagnitudes(samples)
        let db = (0..<count).map { bandDB($0, of: count, sampleRate: sampleRate) }

        referenceDB = max(db.max() ?? -.infinity,
                          max(Self.referenceFloorDB, referenceDB - Self.referenceDecayDB))
        let floorDB = referenceDB - Self.rangeDB

        if levels.count != count { levels = .init(repeating: 0, count: count) }
        for i in 0..<count {
            let target = pow(min(max((db[i] - floorDB) / Self.rangeDB, 0), 1), 1.6)
            levels[i] += (target - levels[i]) * (target > levels[i] ? 0.65 : 0.14)
        }
        return levels
    }

    private func computeMagnitudes(_ samples: [Float]) {
        let windowed = vDSP.multiply(samples, window)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBytes {
                    vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                              &split, 1, vDSP_Length(Self.fftSize / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(kFFTDirection_Forward))
                split.imagp[0] = 0  // Holds the Nyquist term after zrip.
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(Self.fftSize / 2))
            }
        }
    }

    private func bandDB(_ band: Int, of count: Int, sampleRate: Float) -> Float {
        let ratio = Self.maxHz / Self.minHz
        let low = Self.minHz * pow(ratio, Float(band) / Float(count))
        let high = Self.minHz * pow(ratio, Float(band + 1) / Float(count))
        let binHz = sampleRate / Float(Self.fftSize)
        let last = magnitudes.count - 1
        let lowBin = min(low / binHz, Float(last))
        let highBin = min(high / binHz, Float(last))

        var magnitude: Float
        if Int(highBin) > Int(lowBin) {
            magnitude = magnitudes[Int(lowBin)...Int(highBin)].max() ?? 0
        } else {
            // Narrower than one bin: interpolate so low bands do not stair-step.
            let position = (lowBin + highBin) / 2
            let index = min(Int(position), last - 1)
            let fraction = position - Float(index)
            magnitude = magnitudes[index] * (1 - fraction) + magnitudes[index + 1] * fraction
        }
        magnitude *= 4 / Float(Self.fftSize)  // zrip scale (2) and Hann gain (0.5).

        let octavesAbove1k = log2(max(sqrt(low * high), 1) / 1000)
        return 20 * log10(max(magnitude, 1e-9)) + octavesAbove1k * Self.tiltDBPerOctave
    }
}
