/// Serializes a canvas to ANSI, coloured by distance from the centre line.
public enum Renderer {
    public static func frame(_ canvas: Canvas, status: String, palette: Palette) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(canvas.cols * canvas.rows * 3 + canvas.rows * 32)
        out += Array("\u{1B}[H".utf8)
        let mid = Float(canvas.rows - 1) / 2
        for row in 0..<canvas.rows {
            out += Array(color(distance: abs(Float(row) - mid) / max(mid, 1), palette: palette).utf8)
            for col in 0..<canvas.cols {
                appendBraille(canvas.cell(col: col, row: row), to: &out)
            }
            out += Array("\r\n".utf8)
        }
        out += Array("\u{1B}[0m\u{1B}[2m\(status.prefix(canvas.cols))\u{1B}[0m\u{1B}[K".utf8)
        return out
    }

    /// U+2800 + dots. A blank cell is U+2800 too, which keeps row widths equal.
    static func appendBraille(_ dots: UInt8, to out: inout [UInt8]) {
        out.append(0xE2)
        out.append(0xA0 | (dots >> 6))
        out.append(0x80 | (dots & 0x3F))
    }

    private static func color(distance: Float, palette: Palette) -> String {
        let t = min(distance, 1)
        let channel = { (a: Float, b: Float) in Int(a + (b - a) * t) }
        let r = channel(palette.centre.r, palette.edge.r)
        let g = channel(palette.centre.g, palette.edge.g)
        let b = channel(palette.centre.b, palette.edge.b)
        return "\u{1B}[38;2;\(r);\(g);\(b)m"
    }
}
