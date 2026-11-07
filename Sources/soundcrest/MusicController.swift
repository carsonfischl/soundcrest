import Foundation
import WaveCore

/// The playlist browser that replaces the waveform after a click. Main thread only.
final class MusicController {
    private(set) var isOpen = false
    private var view = MusicBrowserView()
    private let signIn = SignIn()
    /// What clicking each row does, from the last `render`.
    private var actions: [MusicAction?] = []
    private var area = 1
    /// Bumped on every navigation so late replies for an old screen are dropped.
    private var generation = 0

    func open() {
        isOpen = true
        show(.home)
    }

    func close() {
        signIn.cancel()
        isOpen = false
    }

    func click(row: Int) {
        guard actions.indices.contains(row - 1), let action = actions[row - 1] else { return }
        perform(action)
    }

    func scroll(_ delta: Int) { perform(.scroll(delta * 3)) }

    func render(width: Int, rows: Int, palette: Palette) -> [UInt8] {
        let columns = width - Panel.margin
        area = rows - 1
        let layout = MusicBrowser.layout(view, width: columns, rows: rows)
        actions = layout.actions
        return Panel.render(layout.lines, firstRow: 1, lastRow: rows, palette: palette)
    }

    private func perform(_ action: MusicAction) {
        switch action {
        case .close:
            close()
        case .back:
            switch view.screen {
            case .home: close()
            case .tracks(let service, _): show(.playlists(service))
            default: show(.home)
            }
        case .scroll(let delta):
            let count = view.message != nil ? 0 : view.screen.isTracks ? view.tracks.count : view.playlists.count
            view.scroll = min(max(view.scroll + delta, 0), MusicBrowser.maxScroll(count: count, area: area))
        case .choose(let service):
            guard let credentials = MusicCredentials.stored(service, in: .standard) else { return show(.setup(service)) }
            guard TokenStore.load(service) != nil else { return startSignIn(service, credentials) }
            show(.playlists(service))
        case .playlist(let playlist):
            if case .playlists(let service) = view.screen { show(.tracks(service, playlist)) }
        case .track(let track):
            guard case .tracks(let service, let playlist) = view.screen else { return }
            play(track, from: playlist, on: service)
        }
    }

    private func show(_ screen: MusicBrowserView.Screen) {
        generation += 1
        if case .signIn = view.screen, screen != view.screen { signIn.cancel() }
        view.screen = screen
        view.scroll = 0
        view.message = nil
        view.loading = false
        view.configured = Set(MusicService.allCases.filter { MusicCredentials.stored($0, in: .standard) != nil })
        view.signedIn = Set(MusicService.allCases.filter { TokenStore.load($0) != nil })
        switch screen {
        case .playlists(let service): loadPlaylists(service)
        case .tracks(let service, let playlist): loadTracks(service, playlist)
        default: break
        }
    }

    private func startSignIn(_ service: MusicService, _ credentials: MusicCredentials) {
        show(.signIn(service))
        let current = generation
        signIn.start(service, credentials: credentials) { [weak self] result in
            guard let self, self.generation == current else { return }
            switch result {
            case .success(let tokens):
                TokenStore.save(tokens, for: service)
                self.show(.playlists(service))
            case .failure(let failure):
                self.view.message = failure.message
            }
        }
    }

    private func loadPlaylists(_ service: MusicService) {
        view.loading = true
        view.playlists = []
        let current = generation
        let done = { [weak self] (result: Result<[Playlist], Failure>) in
            guard let self, self.generation == current else { return }
            self.view.loading = false
            switch result {
            case .success(let playlists): self.view.playlists = playlists
            case .failure(let failure): self.view.message = failure.message
            }
        }
        switch service {
        case .spotify:
            MusicAPI.spotifyPages(SpotifyAPI.playlistsURL, decode: SpotifyAPI.playlists) { result in
                done(result.map { [Playlist(id: Playlist.likedID, name: "Liked Songs", count: nil)] + $0 })
            }
        case .youtube:
            MusicAPI.get(YouTubeAPI.channelURL, .youtube) { channel in
                let liked = (try? channel.get()).flatMap(YouTubeAPI.likesPlaylist)
                    .map { [Playlist(id: $0, name: "Liked videos", count: nil)] } ?? []
                MusicAPI.youtubePages({ YouTubeAPI.playlistsURL(pageToken: $0) }, decode: YouTubeAPI.playlists) { result in
                    done(result.map { liked + $0 })
                }
            }
        }
    }

    private func loadTracks(_ service: MusicService, _ playlist: Playlist) {
        view.loading = true
        view.tracks = []
        let current = generation
        let done = { [weak self] (result: Result<[Track], Failure>) in
            guard let self, self.generation == current else { return }
            self.view.loading = false
            switch result {
            case .success(let tracks): self.view.tracks = tracks
            case .failure(let failure): self.view.message = failure.message
            }
        }
        switch service {
        case .spotify:
            MusicAPI.spotifyPages(SpotifyAPI.itemsURL(playlist: playlist.id), decode: SpotifyAPI.tracks, done)
        case .youtube:
            MusicAPI.youtubePages({ YouTubeAPI.itemsURL(playlist: playlist.id, pageToken: $0) },
                                  decode: YouTubeAPI.tracks, done)
        }
    }

    /// Hands the song to the Spotify app or the browser and goes back to the
    /// waveform, which then shows it playing.
    private func play(_ track: Track, from playlist: Playlist, on service: MusicService) {
        switch service {
        case .spotify:
            let command = Process()
            #if os(macOS)
            command.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            command.arguments = ["-e", SpotifyAPI.playScript(track: track, playlist: playlist)]
            let failure = "Couldn't start Spotify. Is the Spotify app installed, and is your "
                + "terminal allowed to control it under Privacy & Security > Automation?"
            #else
            command.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            command.arguments = ["dbus-send"] + SpotifyAPI.mprisOpenArguments(track: track)
            let failure = "Couldn't reach the Spotify app. Start Spotify, then pick the song again."
            #endif
            command.standardOutput = FileHandle.nullDevice
            command.standardError = FileHandle.nullDevice
            command.terminationHandler = { [weak self] process in
                guard process.terminationStatus != 0 else { return }
                MainLoop.post {
                    guard let self else { return }
                    self.isOpen = true
                    self.view.message = failure
                }
            }
            try? command.run()
        case .youtube:
            openInBrowser(YouTubeAPI.watchURL(track: track, playlist: playlist))
        }
        close()
    }
}

private extension MusicBrowserView.Screen {
    var isTracks: Bool {
        if case .tracks = self { return true }
        return false
    }
}
