/// Parsed command line. `color` and `backdrop` are nil unless passed explicitly.
public struct Options: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case both, terminal, wallpaper, wallpaperRun, toggle, autostart(Bool), pane(Bool), paneShell, paneRun, probe(Double), help
    }

    public var mode = Mode.both
    public var scope = false
    public var color: String?
    public var backdrop: Backdrop?

    /// Nil when the arguments are not valid.
    public static func parse(_ arguments: [String]) -> Options? {
        var options = Options()
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--terminal": options.mode = .terminal
            case "--wallpaper": options.mode = .wallpaper
            case "--wallpaper-run": options.mode = .wallpaperRun
            case "--toggle": options.mode = .toggle
            case "--autostart":
                switch rest.popFirst() {
                case "on": options.mode = .autostart(true)
                case "off": options.mode = .autostart(false)
                default: return nil
                }
            case "--pane":
                switch rest.popFirst() {
                case "on": options.mode = .pane(true)
                case "off": options.mode = .pane(false)
                default: return nil
                }
            case "--pane-shell": options.mode = .paneShell
            case "--pane-run": options.mode = .paneRun
            case "--scope": options.scope = true
            case "--help", "-h": options.mode = .help
            case "--probe":
                guard let seconds = rest.popFirst().flatMap(Double.init) else { return nil }
                options.mode = .probe(seconds)
            case "--color":
                guard let spec = rest.popFirst(), Palette(spec: spec) != nil else { return nil }
                options.color = spec
            case "--backdrop":
                guard let backdrop = rest.popFirst().flatMap(Backdrop.init(rawValue:)) else { return nil }
                options.backdrop = backdrop
            default:
                return nil
            }
        }
        return options
    }
}
