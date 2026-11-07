import Foundation

/// Magnitude spectrum of real samples, in pure Swift so it runs where
/// Accelerate doesn't. Scaled like vDSP's `fft_zrip` (twice the plain DFT,
/// Nyquist dropped from bin 0), because the analyzer's levels are absolute.
public final class RealFFT {
    public let size: Int
    private let half: Int
    private let bitReversed: [Int]
    private let cosines: [Float]
    private let sines: [Float]
    private var real: [Float]
    private var imag: [Float]

    /// `size` must be a power of two, at least 4.
    public init(size: Int) {
        precondition(size >= 4 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        half = size / 2
        let bits = Int(log2(Double(half)))
        bitReversed = (0..<half).map { index in
            var reversed = 0
            for bit in 0..<bits where index & (1 << bit) != 0 { reversed |= 1 << (bits - 1 - bit) }
            return reversed
        }
        cosines = (0..<half).map { Float(cos(2 * Double.pi * Double($0) / Double(size))) }
        sines = (0..<half).map { Float(sin(2 * Double.pi * Double($0) / Double(size))) }
        real = .init(repeating: 0, count: half)
        imag = real
    }

    /// `size / 2` magnitudes, bin `k` at `k * sampleRate / size` Hz.
    public func magnitudes(of samples: [Float]) -> [Float] {
        precondition(samples.count == size)
        // Pack even samples as real parts and odd as imaginary, then run a
        // complex FFT of half the length.
        for index in 0..<half {
            let target = bitReversed[index]
            real[target] = samples[2 * index]
            imag[target] = samples[2 * index + 1]
        }
        var span = 1
        while span < half {
            let step = half / span
            var start = 0
            while start < half {
                for offset in 0..<span {
                    // Twiddle e^(-2πi·offset/(2·span)) is table entry offset·step,
                    // since the tables run over `size` = 2·half points.
                    let angle = offset * step
                    let wr = cosines[angle], wi = -sines[angle]
                    let a = start + offset, b = a + span
                    let tr = real[b] * wr - imag[b] * wi
                    let ti = real[b] * wi + imag[b] * wr
                    real[b] = real[a] - tr
                    imag[b] = imag[a] - ti
                    real[a] += tr
                    imag[a] += ti
                }
                start += 2 * span
            }
            span *= 2
        }

        // Split the half-length result into the real input's spectrum.
        var out = [Float](repeating: 0, count: half)
        out[0] = abs(2 * (real[0] + imag[0]))  // DC; zrip keeps Nyquist in the slot vDSP callers zero.
        for k in 1..<half {
            let j = half - k
            let evenR = (real[k] + real[j]) / 2, evenI = (imag[k] - imag[j]) / 2
            let oddR = (imag[k] + imag[j]) / 2, oddI = -(real[k] - real[j]) / 2
            let wr = cosines[k], wi = -sines[k]
            let xr = evenR + oddR * wr - oddI * wi
            let xi = evenI + oddR * wi + oddI * wr
            out[k] = 2 * (xr * xr + xi * xi).squareRoot()
        }
        return out
    }
}
