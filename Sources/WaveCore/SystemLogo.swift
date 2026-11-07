import Foundation

/// The operating system's logo for the info view, drawn from simple shapes in
/// braille dots so it stays smooth at any size. Each terminal cell holds 2×4
/// dots, and cells are about twice as tall as wide, so a logo `rows` tall is
/// `2 × rows` columns wide and comes out roughly square.
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

    /// `rows` lines of `2 × rows` columns. Empty cells are spaces.
    public func render(rows: Int) -> [String] {
        guard rows > 0 else { return [] }
        let cols = rows * 2
        let width = Double(cols * 2), height = Double(rows * 4)
        return (0..<rows).map { row in
            String((0..<cols).map { col -> Character in
                var dots: UInt32 = 0
                for dx in 0..<2 {
                    for dy in 0..<4 {
                        let x = (Double(col * 2 + dx) + 0.5) / width
                        let y = (Double(row * 4 + dy) + 0.5) / height
                        if contains(x: x, y: y) { dots |= Self.bits[dx][dy] }
                    }
                }
                return dots == 0 ? " " : Character(Unicode.Scalar(0x2800 + dots)!)
            })
        }
    }

    /// Three dots evenly around the ring, starting at 2 o'clock.
    private static let ubuntuDots: [(x: Double, y: Double)] = (0..<3).map { index in
        let angle = Double(index) * 2 * Double.pi / 3 - Double.pi / 6
        return (x: 0.5 + 0.40 * cos(angle), y: 0.5 + 0.40 * sin(angle))
    }

    private static let bits: [[UInt32]] = [[0x01, 0x02, 0x04, 0x40], [0x08, 0x10, 0x20, 0x80]]

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
            let silhouette = circle(x, y, 0.50, 0.24, 0.21) || ellipse(x, y, 0.50, 0.62, 0.34, 0.35)
            let belly = ellipse(x, y, 0.50, 0.68, 0.19, 0.24)
            let eyes = circle(x, y, 0.42, 0.20, 0.05) || circle(x, y, 0.58, 0.20, 0.05)
            let feet = ellipse(x, y, 0.32, 0.96, 0.17, 0.05) || ellipse(x, y, 0.68, 0.96, 0.17, 0.05)
            return (silhouette && !belly && !eyes) || feet
        case .ubuntu:
            let nearest = Self.ubuntuDots.map { distance(x, y, $0.x, $0.y) }.min() ?? 1
            let d = distance(x, y, 0.5, 0.5)
            let ring = d > 0.25 && d < 0.35 && nearest >= 0.17
            return ring || nearest < 0.10
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
            let bubble = circle(x, y, 0.5, 0.5, 0.47) || (x > 0.03 && x < 0.5 && y > 0.5 && y < 0.97)
            let stem = x > 0.45 && x < 0.58 && y > 0.30 && y < 0.78
            let hook = y < 0.33 && x > 0.45 && {
                let d = distance(x, y, 0.65, 0.33)
                return d > 0.07 && d < 0.20
            }()
            let bar = x > 0.32 && x < 0.72 && y > 0.47 && y < 0.57
            return bubble && !(stem || hook || bar)
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
