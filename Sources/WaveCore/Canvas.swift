/// Braille-dot drawing surface: each terminal cell holds 2×4 dots.
public struct Canvas {
    public let cols: Int
    public let rows: Int
    public var dotWidth: Int { cols * 2 }
    public var dotHeight: Int { rows * 4 }
    private var cells: [UInt8]

    private static let bits: [[UInt8]] = [
        [0x01, 0x02, 0x04, 0x40],
        [0x08, 0x10, 0x20, 0x80],
    ]

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        cells = .init(repeating: 0, count: cols * rows)
    }

    public func cell(col: Int, row: Int) -> UInt8 { cells[row * cols + col] }

    /// Fills dots `y0...y1` in column `x`, clipping to the canvas.
    public mutating func vline(x: Int, y0: Int, y1: Int) {
        guard x >= 0, x < dotWidth else { return }
        let top = max(min(y0, y1), 0)
        let bottom = min(max(y0, y1), dotHeight - 1)
        guard top <= bottom else { return }
        for y in top...bottom {
            cells[(y / 4) * cols + x / 2] |= Self.bits[x % 2][y % 4]
        }
    }

    /// Mirrored silhouette: lows at the centre, highs toward both edges.
    public mutating func drawBars(_ levels: [Float]) {
        guard !levels.isEmpty else { return }
        let mid = (dotHeight - 1) / 2
        let centre = Float(dotWidth - 1) / 2
        for x in 0..<dotWidth {
            let distance = abs(Float(x) - centre) / max(centre, 1)
            let level = levels[min(Int(distance * Float(levels.count)), levels.count - 1)]
            let reach = Int(level * Float(mid))
            vline(x: x, y0: mid - reach, y1: mid + reach)
        }
    }

    /// Oscilloscope trace, triggered on a rising zero crossing so it holds still.
    public mutating func drawScope(_ samples: [Float]) {
        let width = dotWidth
        guard samples.count > width else { return }
        let peak = max(samples.lazy.map { abs($0) }.max() ?? 0, 0.02)
        let start = (1..<(samples.count - width)).first {
            samples[$0 - 1] < 0 && samples[$0] >= 0
        } ?? 0
        let mid = (dotHeight - 1) / 2
        var previous = mid
        for x in 0..<width {
            let y = mid - Int(samples[start + x] / peak * Float(mid) * 0.9)
            vline(x: x, y0: previous, y1: y)
            previous = y
        }
    }
}
