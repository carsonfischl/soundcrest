import Foundation

/// Parsed command line. `color` and `backdrop` are nil unless passed explicitly.
public struct Options: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case both, terminal, wallpaper, wallpaperRun, toggle, autostart(Bool), pane(Bool), paneSize(PaneSize), paneShell, paneRun, locate, probe(Double), help
        case paneSection(PaneSection, Bool), weatherLocation(String?), newsSources([NewsSource])
        case musicCredentials(MusicService, MusicCredentials), musicSignOut(MusicService)
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
            case "--pane-size":
                guard let size = rest.popFirst().flatMap(PaneSize.init(spec:)) else { return nil }
                options.mode = .paneSize(size)
            case "--pane-info", "--pane-weather", "--pane-news":
                let section = PaneSection(rawValue: String(argument.dropFirst("--pane-".count)))!
                switch rest.popFirst() {
                case "on": options.mode = .paneSection(section, true)
                case "off": options.mode = .paneSection(section, false)
                default: return nil
                }
            case "--weather-location":
                guard let place = rest.popFirst()?.trimmingCharacters(in: .whitespaces), !place.isEmpty else {
                    return nil
                }
                options.mode = .weatherLocation(place.lowercased() == "auto" ? nil : place)
            case "--news-sources":
                guard let sources = rest.popFirst().flatMap(NewsSource.list) else { return nil }
                options.mode = .newsSources(sources)
            case "--spotify-client-id":
                guard let id = rest.popFirst()?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
                options.mode = .musicCredentials(.spotify, MusicCredentials(clientID: id, clientSecret: nil))
            case "--youtube-client":
                guard let id = rest.popFirst()?.trimmingCharacters(in: .whitespaces), !id.isEmpty,
                      let secret = rest.popFirst()?.trimmingCharacters(in: .whitespaces), !secret.isEmpty else {
                    return nil
                }
                options.mode = .musicCredentials(.youtube, MusicCredentials(clientID: id, clientSecret: secret))
            case "--music-sign-out":
                guard let service = rest.popFirst().flatMap({ MusicService(rawValue: $0.lowercased()) }) else {
                    return nil
                }
                options.mode = .musicSignOut(service)
            case "--pane-shell": options.mode = .paneShell
            case "--pane-run": options.mode = .paneRun
            case LocationApp.runFlag: options.mode = .locate
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
