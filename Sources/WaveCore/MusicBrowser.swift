/// The playlist browser that takes the waveform's place when you click it.
public struct MusicBrowserView: Equatable, Sendable {
    public enum Screen: Equatable, Sendable {
        case home
        /// Credentials missing: shows how to add them.
        case setup(MusicService)
        /// Waiting for the browser to come back from the sign-in page.
        case signIn(MusicService)
        case playlists(MusicService)
        case tracks(MusicService, Playlist)
    }

    public var screen = Screen.home
    public var configured: Set<MusicService> = []
    public var signedIn: Set<MusicService> = []
    public var loading = false
    /// An error or notice shown in place of the list.
    public var message: String?
    public var playlists: [Playlist] = []
    public var tracks: [Track] = []
    /// First list row shown.
    public var scroll = 0

    public init() {}
}

public enum MusicAction: Equatable, Sendable {
    case close, back
    case scroll(Int)
    case choose(MusicService)
    case playlist(Playlist)
    case track(Track)
}

public enum MusicBrowser {
    /// Exactly `rows` lines, plus what clicking each one does.
    public static func layout(_ view: MusicBrowserView, width: Int, rows: Int) -> (lines: [PanelLine], actions: [MusicAction?]) {
        guard rows > 0, width >= 10 else { return ([], []) }
        var lines: [PanelLine] = [header(view.screen, width: width)]
        var actions: [MusicAction?] = [view.screen == .home ? .close : .back]
        let area = rows - 1

        let entries: [(PanelLine, MusicAction?)]
        if let message = view.message {
            entries = Panel.wrap(message, width: width, maxLines: area).map { ([Span($0)], nil) }
        } else {
            switch view.screen {
            case .home:
                entries = home(view, width: width)
            case .setup(let service):
                entries = Panel.wrap(setupText(service), width: width, maxLines: area).map { ([Span($0)], nil) }
            case .signIn(let service):
                entries = Panel.wrap("Finish signing in to \(service.title) in your browser.", width: width,
                                     maxLines: area - 1).map { ([Span($0)], nil) }
                    + [([Span("Cancel", .accent(0))], .back)]
            case .playlists:
                entries = view.playlists.map { playlist in
                    let count = playlist.count.map { "  \($0)" } ?? ""
                    return (Panel.clipped([Span(playlist.name), Span(count, .dim)], to: width), .playlist(playlist))
                }
            case .tracks:
                entries = view.tracks.map { track in
                    let artist = track.artist.isEmpty ? "" : "  " + track.artist
                    return (Panel.clipped([Span(track.title), Span(artist, .dim)], to: width), .track(track))
                }
            }
        }

        if entries.isEmpty, view.loading {
            lines.append([Span("Loading…", .dim)])
            actions.append(nil)
        } else if entries.isEmpty, view.message == nil, view.screen != .home {
            lines.append([Span("Nothing here.", .dim)])
            actions.append(nil)
        }

        let window = visible(count: entries.count, scroll: view.scroll, area: area - (lines.count - 1))
        if window.up {
            lines.append([Span("▴ more", .dim)])
            actions.append(.scroll(-max(window.range.count, 1)))
        }
        for (line, action) in entries[window.range] {
            lines.append(line)
            actions.append(action)
        }
        if window.down > 0 {
            lines.append([Span("▾ \(window.down) more", .dim)])
            actions.append(.scroll(max(window.range.count, 1)))
        }
        while lines.count < rows {
            lines.append([])
            actions.append(nil)
        }
        return (Array(lines.prefix(rows)), Array(actions.prefix(rows)))
    }

    /// Which entries fit, leaving rows for "more" markers when needed.
    static func visible(count: Int, scroll: Int, area: Int) -> (range: Range<Int>, up: Bool, down: Int) {
        guard area > 0, count > 0 else { return (0..<0, false, 0) }
        guard count > area else { return (0..<count, false, 0) }
        let top = min(max(scroll, 0), count - 1)
        let up = top > 0
        var room = area - (up ? 1 : 0)
        if top + room < count { room -= 1 }
        let end = min(top + max(room, 1), count)
        return (top..<end, up, count - end)
    }

    /// Largest useful scroll position, so paging never runs off the end.
    public static func maxScroll(count: Int, area: Int) -> Int { max(count - max(area - 2, 1), 0) }

    private static func header(_ screen: MusicBrowserView.Screen, width: Int) -> PanelLine {
        switch screen {
        case .home:
            let title: PanelLine = [Span("♪ Play from", .accentBold(0))]
            let close = "✕ close"
            let gap = width - Panel.width(title) - close.count
            return gap >= 1 ? title + [Span(String(repeating: " ", count: gap)), Span(close, .dim)] : title
        case .setup(let service), .signIn(let service), .playlists(let service):
            return [Span("‹ ", .dim), Span(service.title, .accentBold(0))]
        case .tracks(let service, let playlist):
            return Panel.clipped([Span("‹ ", .dim), Span(service.title, .accentBold(0)), Span(" › ", .dim),
                                  Span(playlist.name, .bold)], to: width)
        }
    }

    private static func home(_ view: MusicBrowserView, width: Int) -> [(PanelLine, MusicAction?)] {
        [([Span("● ", .accent(0)), Span("System audio", .bold), Span("  listening", .dim)], .close)]
            + MusicService.allCases.map { service in
                let status = !view.configured.contains(service) ? "  set up"
                    : !view.signedIn.contains(service) ? "  sign in" : ""
                return (Panel.clipped([Span("○ ", .dim), Span(service.title), Span(status, .dim)], to: width),
                        .choose(service))
            }
    }

    static func setupText(_ service: MusicService) -> String {
        switch service {
        case .spotify:
            return "Spotify needs an app you register at developer.spotify.com (Premium required) with redirect URI "
                + "\(MusicAuth.redirect). Then run: soundcrest --spotify-client-id ID"
        case .youtube:
            return "YouTube needs a Google Cloud OAuth client of type Desktop app, with the YouTube Data API "
                + "enabled. Then run: soundcrest --youtube-client ID SECRET"
        }
    }
}
