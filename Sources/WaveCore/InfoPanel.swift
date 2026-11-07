/// Neofetch-style system summary.
public enum InfoPanel {
    public struct Field: Equatable, Sendable {
        public let label: String
        public let value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    /// Tallest the logo grows, in rows.
    static let maximumLogoRows = 16

    /// Fits the summary into `rows` × `width`, with `logo` centred above it,
    /// as large as the room allows. The details always come first: the logo
    /// appears only beside a full set of fields, and is left out when even
    /// the smallest one won't fit. After that, decoration goes before fields.
    public static func layout(header: String, fields: [Field], width: Int, rows: Int,
                              logo: SystemLogo? = nil) -> [PanelLine] {
        guard rows > 0, width >= 8 else { return [] }
        let details = candidates(header: header, fields: fields, width: width)
        if let logo {
            // Full details with or without the swatch, then title and fields.
            for text in details.prefix(3) {
                let logoRows = min(maximumLogoRows, rows - text.count - 1, width / 2)
                guard logoRows >= SystemLogo.minimumRows else { continue }
                let indent = Span(String(repeating: " ", count: (width - logoRows * 2) / 2))
                let art = logo.quadrants(rows: logoRows).enumerated().map { row, cells in
                    [indent] + logoSpans(cells, shade: Float(row) / Float(max(logoRows - 1, 1)))
                }
                return art + [[]] + text
            }
        }
        return Panel.firstFitting(details, rows: rows)
    }

    /// Turns a row of quadrant masks into spans. Whole cells are filled with
    /// background colour and cells missing one quarter are drawn in reverse,
    /// so most of the logo covers the full cell, including the gap some
    /// terminals leave between rows of block glyphs. Other edges are glyphs.
    static func logoSpans(_ cells: [Int], shade: Float) -> PanelLine {
        var spans: PanelLine = []
        for mask in cells {
            let span: Span
            switch mask {
            case 15: span = Span(" ", .fill(shade))
            case 7, 11, 13, 14: span = Span(String(SystemLogo.quadrantGlyphs[15 - mask]), .cutout(shade))
            default: span = Span(String(SystemLogo.quadrantGlyphs[mask]), .accent(shade))
            }
            if let last = spans.last, last.style == span.style {
                spans[spans.count - 1] = Span(last.text + span.text, span.style)
            } else {
                spans.append(span)
            }
        }
        // Trailing blanks would only pad the line.
        if let last = spans.last, last.style == .accent(shade) {
            let trimmed = String(last.text.reversed().drop { $0 == " " }.reversed())
            spans.removeLast()
            if !trimmed.isEmpty { spans.append(Span(trimmed, last.style)) }
        }
        return spans
    }

    private static func candidates(header: String, fields: [Field], width: Int) -> [[PanelLine]] {
        let shown = fields.map { field in
            Panel.clipped([Span(field.label + ": ", .accentBold(0)), Span(field.value)], to: width)
        }
        let title: PanelLine = [Span(Panel.truncated(header, to: width), .accentBold(0))]
        let rule: PanelLine = [Span(String(repeating: "─", count: min(header.count, width)), .dim)]
        let swatchWidth = min(width, 24)
        let swatch: PanelLine = (0..<swatchWidth).map {
            Span("█", .accent(Float($0) / Float(max(swatchWidth - 1, 1))))
        }
        return [
            [title, rule] + shown + [swatch],
            [title, rule] + shown,
            [title] + shown,
            shown,
        ]
    }

    /// `3d 4h 12m`, dropping leading zero units.
    public static func uptime(seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// `8.2 / 18.0 GiB (45%)`.
    public static func usage(used: UInt64, total: UInt64) -> String {
        guard total > 0 else { return "?" }
        let gib = { (bytes: UInt64) in Double(bytes) / 1_073_741_824 }
        let percent = Int((Double(used) / Double(total) * 100).rounded())
        return "\(oneDecimal(gib(used))) / \(oneDecimal(gib(total))) GiB (\(percent)%)"
    }

    private static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }
}
