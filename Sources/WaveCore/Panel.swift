/// A run of text in one style. `accent` takes a colour `t` of the way from the
/// palette's centre to its edge.
public struct Span: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case plain, bold, dim
        case accent(Float)
        case accentBold(Float)
    }

    public let text: String
    public let style: Style

    public init(_ text: String, _ style: Style = .plain) {
        self.text = text
        self.style = style
    }
}

public typealias PanelLine = [Span]

/// Drawing helpers shared by the sections under the pane's waveform.
public enum Panel {
    /// Left margin, in columns.
    public static let margin = 1

    /// ANSI for rows `firstRow...lastRow` (1-based). `lines` are bottom-aligned
    /// and every row in the range is cleared so stale text never lingers.
    public static func render(_ lines: [PanelLine], firstRow: Int, lastRow: Int, palette: Palette) -> [UInt8] {
        guard firstRow <= lastRow else { return [] }
        let start = lastRow - lines.count + 1
        var out = ""
        for row in firstRow...lastRow {
            out += "\u{1B}[\(row);1H\u{1B}[0m\u{1B}[K"
            guard row >= start else { continue }
            out += String(repeating: " ", count: margin)
            for span in lines[row - start] {
                out += code(span.style, palette: palette) + span.text + "\u{1B}[0m"
            }
        }
        return Array(out.utf8)
    }

    private static func code(_ style: Span.Style, palette: Palette) -> String {
        switch style {
        case .plain: return ""
        case .bold: return "\u{1B}[1m"
        case .dim: return "\u{1B}[2m"
        case .accent(let t): return foreground(palette.mix(t))
        case .accentBold(let t): return "\u{1B}[1m" + foreground(palette.mix(t))
        }
    }

    private static func foreground(_ color: RGB) -> String {
        "\u{1B}[38;2;\(Int(color.r));\(Int(color.g));\(Int(color.b))m"
    }

    /// Visible width of a line, counting one column per character.
    public static func width(_ line: PanelLine) -> Int { line.reduce(0) { $0 + $1.text.count } }

    /// Cuts a line to `width` columns, ending in `…` when anything was dropped.
    public static func clipped(_ line: PanelLine, to width: Int) -> PanelLine {
        guard Self.width(line) > width else { return line }
        var out: PanelLine = []
        var room = width
        for span in line {
            guard room > 0 else { break }
            let text = truncated(span.text, to: room)
            out.append(Span(text, span.style))
            room -= text.count
            if text != span.text { break }
        }
        if Self.width(out) == width, let last = out.last, !last.text.hasSuffix("…") {
            out[out.count - 1] = Span(String(last.text.dropLast()) + "…", last.style)
        }
        return out
    }

    public static func truncated(_ text: String, to width: Int) -> String {
        guard text.count > width else { return text }
        guard width > 0 else { return "" }
        return text.prefix(width - 1) + "…"
    }

    /// Word-wraps `text` to `width`, at most `maxLines`, ending in `…` if cut.
    public static func wrap(_ text: String, width: Int, maxLines: Int) -> [String] {
        guard width > 0, maxLines > 0 else { return [] }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var lines: [String] = []
        var next = 0
        while next < words.count, lines.count < maxLines {
            var line = truncated(words[next], to: width)
            next += 1
            while next < words.count, line.count + 1 + words[next].count <= width {
                line += " " + words[next]
                next += 1
            }
            lines.append(line)
        }
        if next < words.count, let last = lines.last, !last.hasSuffix("…") {
            lines[lines.count - 1] = last.count < width ? last + "…" : last.prefix(width - 1) + "…"
        }
        return lines
    }

    /// `info  weather  news   ⌥⇥`, with the active tab in colour.
    public static func tabBar(_ sections: [PaneSection], active: PaneSection, width: Int) -> PanelLine {
        var line: PanelLine = []
        for (index, section) in sections.enumerated() {
            if index > 0 { line.append(Span("  ")) }
            line.append(section == active ? Span(section.title, .accentBold(0)) : Span(section.title, .dim))
        }
        let hint = "⌥⇥"
        let gap = width - Self.width(line) - hint.count
        if gap >= 2 { line += [Span(String(repeating: " ", count: gap)), Span(hint, .dim)] }
        return clipped(line, to: width)
    }

    /// Pane columns (1-based, after the margin) covered by each tab label in
    /// `tabBar`, for telling which one was clicked.
    public static func tabTargets(_ sections: [PaneSection], width: Int) -> [(columns: ClosedRange<Int>, section: PaneSection)] {
        var column = margin + 1
        var targets: [(columns: ClosedRange<Int>, section: PaneSection)] = []
        for section in sections {
            let last = min(column + section.title.count - 1, margin + width)
            if column <= last { targets.append((column...last, section)) }
            column += section.title.count + 2
        }
        return targets
    }

    /// Picks the first candidate layout that fits in `rows`, else the last one
    /// cut down to its first `rows` lines.
    public static func firstFitting(_ candidates: [[PanelLine]], rows: Int) -> [PanelLine] {
        guard rows > 0 else { return [] }
        if let fit = candidates.first(where: { $0.count <= rows }) { return fit }
        return Array((candidates.last ?? []).prefix(rows))
    }
}

extension Palette {
    /// Colour `t` of the way from centre to edge.
    public func mix(_ t: Float) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(r: centre.r + (edge.r - centre.r) * t,
                   g: centre.g + (edge.g - centre.g) * t,
                   b: centre.b + (edge.b - centre.b) * t)
    }
}
