import Foundation

/// The operating system's logo for the info view, drawn from simple shapes so
/// one drawing works at any size. It is rendered in quadrant blocks (2×2 per
/// cell): braille dots looked grainy, and block glyphs alone leave a gap
/// between rows in Terminal, so the info view fills whole cells with
/// background colour and uses glyphs only along the edges.
public enum SystemLogo: String, CaseIterable, Sendable {
    case apple, tux, ubuntu, debian, fedora, arch

    /// Smallest height that still reads as the logo.
    public static let minimumRows = 5

    /// The logo for an /etc/os-release, matching `ID` first and then
    /// `ID_LIKE`, so Mint gets Ubuntu's and Manjaro gets Arch's. Tux otherwise.
    public static func linux(osRelease: String) -> SystemLogo {
        let fields = Dictionary(osRelease.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).lowercased())
        }, uniquingKeysWith: { first, _ in first })
        let ids = [fields["ID"] ?? ""] + (fields["ID_LIKE"] ?? "").split(separator: " ").map(String.init)
        let logos: [String: SystemLogo] = ["ubuntu": .ubuntu, "debian": .debian, "fedora": .fedora,
                                          "rhel": .fedora, "arch": .arch]
        return ids.lazy.compactMap { logos[$0] }.first ?? .tux
    }

    /// Which quarters of each cell are inked: `rows` lines of `2 × rows`
    /// cells, each 0…15 with top-left 1, top-right 2, bottom-left 4 and
    /// bottom-right 8. Cells are twice as tall as wide, so the logo is square.
    public func quadrants(rows: Int) -> [[Int]] {
        guard rows > 0 else { return [] }
        let cols = rows * 2
        let width = Double(cols * 2), height = Double(rows * 2)
        return (0..<rows).map { row in
            (0..<cols).map { col in
                var mask = 0
                for (bit, (dx, dy)) in [(0, 0), (1, 0), (0, 1), (1, 1)].enumerated() {
                    let x = (Double(col * 2 + dx) + 0.5) / width
                    let y = (Double(row * 2 + dy) + 0.5) / height
                    if contains(x: x, y: y) { mask |= 1 << bit }
                }
                return mask
            }
        }
    }

    /// The logo as quadrant-block text, `rows` lines of `2 × rows` columns.
    public func render(rows: Int) -> [String] {
        quadrants(rows: rows).map { String($0.map { Self.quadrantGlyphs[$0] }) }
    }

    /// Indexed by the quadrant mask from `quadrants(rows:)`.
    public static let quadrantGlyphs: [Character] = [" ", "▘", "▝", "▀", "▖", "▌", "▞", "▛",
                                                      "▗", "▚", "▐", "▜", "▄", "▙", "▟", "█"]

    /// Three dots evenly around the ring: right, lower left and upper left.
    private static let ubuntuDots: [(x: Double, y: Double)] = (0..<3).map { index in
        let angle = Double(index) * 2 * Double.pi / 3
        return (x: 0.5 + 0.38 * cos(angle), y: 0.5 + 0.38 * sin(angle))
    }

    /// Whether the point (0…1 across, 0…1 down) is inked.
    func contains(x: Double, y: Double) -> Bool {
        switch self {
        case .apple:
            let body = ellipse(x, y, 0.36, 0.62, 0.30, 0.33) || ellipse(x, y, 0.64, 0.62, 0.30, 0.33)
                || ellipse(x, y, 0.50, 0.55, 0.36, 0.28)
            let carved = circle(x, y, 0.50, 0.24, 0.10) || circle(x, y, 0.50, 1.00, 0.08)
                || circle(x, y, 1.02, 0.52, 0.21)  // the bite
            let leaf = rotatedEllipse(x, y, 0.60, 0.11, 0.14, 0.055, angle: -0.75)
            return (body && !carved) || leaf
        case .tux:
            let head = ellipse(x, y, 0.50, 0.24, 0.20, 0.20)
            let body = ellipse(x, y, 0.50, 0.60, 0.31, 0.37)
            let flippers = rotatedEllipse(x, y, 0.21, 0.62, 0.07, 0.22, angle: 0.25)
                || rotatedEllipse(x, y, 0.79, 0.62, 0.07, 0.22, angle: -0.25)
            let belly = ellipse(x, y, 0.50, 0.66, 0.20, 0.27)
            let face = ellipse(x, y, 0.50, 0.27, 0.13, 0.11)
            let pupils = circle(x, y, 0.45, 0.24, 0.035) || circle(x, y, 0.55, 0.24, 0.035)
            let beak = ellipse(x, y, 0.50, 0.335, 0.08, 0.035)
            let feet = ellipse(x, y, 0.35, 0.965, 0.15, 0.035) || ellipse(x, y, 0.65, 0.965, 0.15, 0.035)
            let dark = (head || body || flippers) && !belly && !face
            return dark || pupils || beak || feet
        case .ubuntu:
            // A ring broken where each of three dots sits just outside it.
            let d = distance(x, y, 0.5, 0.5)
            let nearest = Self.ubuntuDots.map { distance(x, y, $0.x, $0.y) }.min() ?? 1
            let ring = d > 0.24 && d < 0.33 && nearest >= 0.16
            return ring || nearest < 0.085
        case .debian:
            // An Archimedean spiral that thickens as it opens out.
            let dx = x - 0.47, dy = y - 0.55
            let r = (dx * dx + dy * dy).squareRoot()
            var angle = atan2(-dy, dx)
            if angle < 0 { angle += 2 * Double.pi }
            for turn in 0..<3 {
                let theta = angle + Double(turn) * 2 * Double.pi
                guard theta < 2.4 * Double.pi else { break }
                let center = 0.03 + 0.05 * theta
                if abs(r - center) < 0.012 + 0.011 * theta { return true }
            }
            return false
        case .fedora:
            // A speech bubble with an "f" cut out, hooked right at the top and
            // left at the bottom.
            let bubble = circle(x, y, 0.5, 0.5, 0.47) || (x > 0.03 && x < 0.5 && y > 0.5 && y < 0.97)
            let stem = x > 0.44 && x < 0.56 && y > 0.33 && y < 0.67
            let top = distance(x, y, 0.645, 0.34)
            let topHook = y <= 0.34 && top > 0.085 && top < 0.205
            let bottom = distance(x, y, 0.355, 0.66)
            let bottomHook = y >= 0.66 && bottom > 0.085 && bottom < 0.205
            let bar = x > 0.30 && x < 0.70 && y > 0.45 && y < 0.55
            return bubble && !(stem || topHook || bottomHook || bar)
        case .arch:
            let triangle = y > 0.02 && abs(x - 0.5) < 0.48 * y
            let arch = ellipse(x, y, 0.5, 1.02, 0.18, 0.40)
            return triangle && !arch
        }
    }
}

private func distance(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double) -> Double {
    ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
}

private func circle(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ r: Double) -> Bool {
    distance(x, y, cx, cy) < r
}

private func ellipse(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Bool {
    let u = (x - cx) / rx, v = (y - cy) / ry
    return u * u + v * v < 1
}

private func rotatedEllipse(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double,
                            angle: Double) -> Bool {
    let dx = x - cx, dy = y - cy
    let u = (dx * cos(angle) + dy * sin(angle)) / rx
    let v = (-dx * sin(angle) + dy * cos(angle)) / ry
    return u * u + v * v < 1
}
