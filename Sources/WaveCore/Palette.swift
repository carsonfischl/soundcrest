/// An sRGB colour with channels in 0...255.
public struct RGB: Equatable, Sendable {
    public var r, g, b: Float

    public init(r: Float, g: Float, b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(r: Float(value >> 16 & 0xFF), g: Float(value >> 8 & 0xFF), b: Float(value & 0xFF))
    }
}

/// Waveform colours: `centre` at the middle of the wave, `edge` at its tips.
public struct Palette: Equatable, Sendable {
    public static let defaultName = "aurora"
    public static let presets: [String: Palette] = [
        "aurora": Palette(centre: RGB(r: 70, g: 225, b: 210), edge: RGB(r: 235, g: 70, b: 170)),
        "ember": Palette(centre: RGB(r: 255, g: 210, b: 60), edge: RGB(r: 230, g: 50, b: 45)),
        "ocean": Palette(centre: RGB(r: 100, g: 230, b: 255), edge: RGB(r: 30, g: 80, b: 220)),
        "forest": Palette(centre: RGB(r: 180, g: 240, b: 90), edge: RGB(r: 20, g: 140, b: 90)),
        "violet": Palette(centre: RGB(r: 225, g: 170, b: 255), edge: RGB(r: 110, g: 50, b: 230)),
        "mono": Palette(centre: RGB(r: 255, g: 255, b: 255), edge: RGB(r: 140, g: 140, b: 150)),
    ]

    public var centre, edge: RGB

    public init(centre: RGB, edge: RGB) {
        self.centre = centre
        self.edge = edge
    }

    /// A preset name, one hex colour, or `centre,edge` hex colours.
    public init?(spec: String) {
        if let preset = Self.presets[spec.lowercased()] {
            self = preset
            return
        }
        let colors = spec.split(separator: ",", omittingEmptySubsequences: false).map { RGB(hex: String($0)) }
        guard (1...2).contains(colors.count), let centre = colors[0], let edge = colors[colors.count - 1] else {
            return nil
        }
        self.init(centre: centre, edge: edge)
    }
}

/// What the desktop background shows behind the waveform.
public enum Backdrop: String, CaseIterable, Sendable {
    case solid, translucent, transparent

    public var alpha: Float {
        switch self {
        case .solid: return 1
        case .translucent: return 0.55
        case .transparent: return 0
        }
    }
}
