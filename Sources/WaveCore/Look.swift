import Foundation

/// Colours and backdrop. Explicit flags are remembered for later runs, so
/// `--toggle` and bare `soundcrest` bring back the last choice.
public struct Look {
    private static let colorKey = "color"
    private static let backdropKey = "backdrop"

    public let color: String
    public let backdrop: Backdrop

    public var palette: Palette { Palette(spec: color) ?? Palette.presets[Palette.defaultName]! }

    public static func resolve(_ options: Options, store: UserDefaults?) -> Look {
        if let color = options.color { store?.set(color, forKey: colorKey) }
        if let backdrop = options.backdrop { store?.set(backdrop.rawValue, forKey: backdropKey) }
        let storedBackdrop = store?.string(forKey: backdropKey).flatMap(Backdrop.init(rawValue:))
        return Look(color: options.color ?? store?.string(forKey: colorKey) ?? Palette.defaultName,
                    backdrop: options.backdrop ?? storedBackdrop ?? .solid)
    }
}
