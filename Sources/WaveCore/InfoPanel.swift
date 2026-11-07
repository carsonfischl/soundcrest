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

    /// Fits the summary into `rows` × `width`, dropping decoration before data
    /// and later fields before earlier ones.
    public static func layout(header: String, fields: [Field], width: Int, rows: Int) -> [PanelLine] {
        guard rows > 0, width >= 8 else { return [] }
        return Panel.firstFitting(candidates(header: header, fields: fields, width: width), rows: rows)
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
