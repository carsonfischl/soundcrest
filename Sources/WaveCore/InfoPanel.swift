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

    /// Columns between the logo and the details.
    static let logoGap = 2
    /// Narrowest the details may get before the logo is left out.
    static let minimumTextWidth = 26

    /// Fits the summary into `rows` × `width`, with `logo` to its left when
    /// there is room. Drops the logo first, then decoration, then later fields.
    public static func layout(header: String, fields: [Field], width: Int, rows: Int,
                              logo: [String] = []) -> [PanelLine] {
        guard rows > 0, width >= 8 else { return [] }
        let logoWidth = logo.map(\.count).max() ?? 0
        let textWidth = width - logoWidth - logoGap
        guard !logo.isEmpty, textWidth >= minimumTextWidth, rows >= logo.count else {
            return Panel.firstFitting(candidates(header: header, fields: fields, width: width), rows: rows)
        }
        let text = Panel.firstFitting(candidates(header: header, fields: fields, width: textWidth), rows: rows)
        let gap = Span(String(repeating: " ", count: logoGap))
        return (0..<max(text.count, logo.count)).map { row in
            let art = row < logo.count
                ? Span(logo[row], .accent(Float(row) / Float(max(logo.count - 1, 1))))
                : Span(String(repeating: " ", count: logoWidth))
            return row < text.count ? [art, gap] + text[row] : [art]
        }
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
