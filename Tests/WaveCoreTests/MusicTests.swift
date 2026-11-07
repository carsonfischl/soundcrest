import Foundation
import Testing
@testable import WaveCore

private func text(_ lines: [PanelLine]) -> [String] { lines.map { $0.map(\.text).joined() } }
private func json(_ string: String) -> Data { Data(string.utf8) }

// MARK: OAuth

@Test func authorizeURLsUsePKCEAndTheLoopbackRedirect() {
    let spotify = MusicAuth.authorizeURL(.spotify, clientID: "abc", challenge: "ch", state: "st")
    let items = URLComponents(url: spotify, resolvingAgainstBaseURL: false)!.queryItems!
    let value = { (name: String) in items.first { $0.name == name }?.value }
    #expect(spotify.host == "accounts.spotify.com")
    #expect(value("redirect_uri") == "http://127.0.0.1:47823/callback")
    #expect(value("code_challenge_method") == "S256" && value("code_challenge") == "ch" && value("state") == "st")
    #expect(value("scope")!.contains("playlist-read-private"))

    let youtube = MusicAuth.authorizeURL(.youtube, clientID: "g", challenge: "c", state: "s").absoluteString
    #expect(youtube.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth?"))
    #expect(youtube.contains("youtube.readonly") && youtube.contains("access_type=offline"))
}

@Test func callbackReadsCodeStateAndErrors() {
    let ok = MusicAuth.callback(requestLine: "GET /callback?code=a%2Fb&state=xyz HTTP/1.1")
    #expect(ok?.code == "a/b" && ok?.state == "xyz" && ok?.error == nil)
    #expect(MusicAuth.callback(requestLine: "GET /callback?error=access_denied&state=x HTTP/1.1")?.error == "access_denied")
    #expect(MusicAuth.callback(requestLine: "GET /favicon.ico HTTP/1.1") == nil)
    #expect(MusicAuth.callback(requestLine: "POST /callback?code=a HTTP/1.1") == nil)
}

@Test func tokenFormsIncludeSecretOnlyWhenThereIsOne() {
    let spotify = MusicAuth.exchangeForm(code: "c", verifier: "v", credentials: MusicCredentials(clientID: "id", clientSecret: nil))
    #expect(spotify["client_secret"] == nil && spotify["code_verifier"] == "v" && spotify["grant_type"] == "authorization_code")
    let google = MusicAuth.refreshForm(refreshToken: "r", credentials: MusicCredentials(clientID: "id", clientSecret: "s"))
    #expect(google == ["grant_type": "refresh_token", "refresh_token": "r", "client_id": "id", "client_secret": "s"])
    #expect(String(decoding: MusicAuth.formBody(["b": "x y&z", "a": "1"]), as: UTF8.self) == "a=1&b=x%20y%26z")
}

@Test func tokensDecodeAndKeepOldRefreshToken() {
    let now = Date(timeIntervalSince1970: 1000)
    let first = Tokens.decode(json(#"{"access_token":"A","refresh_token":"R","expires_in":3600}"#), now: now)
    #expect(first == Tokens(access: "A", refresh: "R", expires: now.addingTimeInterval(3540)))
    let refreshed = Tokens.decode(json(#"{"access_token":"B","expires_in":3600}"#), previous: "R", now: now)
    #expect(refreshed?.refresh == "R")
    #expect(Tokens.decode(json(#"{"error":"invalid_grant"}"#)) == nil)
}

@Test func credentialsNeedASecretForYouTubeOnly() {
    let store = UserDefaults(suiteName: "soundcrest-tests-\(UUID())")!
    #expect(MusicCredentials.stored(.spotify, in: store) == nil)
    MusicCredentials(clientID: "sp", clientSecret: nil).save(.spotify, in: store)
    #expect(MusicCredentials.stored(.spotify, in: store) == MusicCredentials(clientID: "sp", clientSecret: nil))
    MusicCredentials(clientID: "yt", clientSecret: nil).save(.youtube, in: store)
    #expect(MusicCredentials.stored(.youtube, in: store) == nil)
    MusicCredentials(clientID: "yt", clientSecret: "sec").save(.youtube, in: store)
    #expect(MusicCredentials.stored(.youtube, in: store)?.clientSecret == "sec")
}

@Test func optionsParseMusicSetup() {
    #expect(Options.parse(["--spotify-client-id", "abc"])?.mode
        == .musicCredentials(.spotify, MusicCredentials(clientID: "abc", clientSecret: nil)))
    #expect(Options.parse(["--youtube-client", "id", "secret"])?.mode
        == .musicCredentials(.youtube, MusicCredentials(clientID: "id", clientSecret: "secret")))
    #expect(Options.parse(["--youtube-client", "id"]) == nil)
    #expect(Options.parse(["--music-sign-out", "Spotify"])?.mode == .musicSignOut(.spotify))
    #expect(Options.parse(["--music-sign-out", "tidal"]) == nil)
}

// MARK: Spotify

@Test func spotifyPlaylistsDecodeOldAndNewCountFields() {
    let page = SpotifyAPI.playlists(json("""
    {"items":[{"id":"p1","name":"Mix","items":{"total":12}},{"id":"p2","name":"Old","tracks":{"total":3}},null],
     "next":"https://api.spotify.com/v1/me/playlists?offset=50"}
    """))
    #expect(page?.items == [Playlist(id: "p1", name: "Mix", count: 12), Playlist(id: "p2", name: "Old", count: 3)])
    #expect(page?.next?.absoluteString.contains("offset=50") == true)
}

@Test func spotifyTracksReadItemOrTrackAndSkipEpisodes() {
    let page = SpotifyAPI.tracks(json("""
    {"items":[
      {"item":{"uri":"spotify:track:1","name":"One","type":"track","artists":[{"name":"A"},{"name":"B"}]}},
      {"track":{"uri":"spotify:track:2","name":"Two","artists":[{"name":"C"}]}},
      {"item":{"uri":"spotify:episode:3","name":"Pod","type":"episode"}},
      {"track":{"uri":"spotify:local:x","name":"Local","is_local":true}},
      {"item":null}
    ],"next":null}
    """))
    #expect(page?.items == [Track(id: "spotify:track:1", title: "One", artist: "A, B"),
                            Track(id: "spotify:track:2", title: "Two", artist: "C")])
    #expect(page?.next == nil)
}

@Test func spotifyURLsAndPlayScript() {
    #expect(SpotifyAPI.itemsURL(playlist: "abc").absoluteString == "https://api.spotify.com/v1/playlists/abc/items?limit=50")
    #expect(SpotifyAPI.itemsURL(playlist: Playlist.likedID) == SpotifyAPI.likedURL)
    let track = Track(id: "spotify:track:1", title: "t", artist: "a")
    #expect(SpotifyAPI.playScript(track: track, playlist: Playlist(id: "p\"x", name: "n", count: nil))
        == #"tell application "Spotify" to play track "spotify:track:1" in context "spotify:playlist:px""#)
    #expect(SpotifyAPI.playScript(track: track, playlist: Playlist(id: Playlist.likedID, name: "n", count: nil))
        == #"tell application "Spotify" to play track "spotify:track:1""#)
}

// MARK: YouTube

@Test func youtubeDecodesPlaylistsItemsAndLikes() {
    let playlists = YouTubeAPI.playlists(json("""
    {"items":[{"id":"PL1","snippet":{"title":"Road trip"},"contentDetails":{"itemCount":20}}],"nextPageToken":"N"}
    """))
    #expect(playlists?.items == [Playlist(id: "PL1", name: "Road trip", count: 20)])
    #expect(playlists?.nextPage == "N")

    let tracks = YouTubeAPI.tracks(json("""
    {"items":[
      {"snippet":{"title":"Song","videoOwnerChannelTitle":"Band - Topic","resourceId":{"videoId":"v1"}}},
      {"snippet":{"title":"Deleted video","resourceId":{"videoId":"v2"}}}
    ]}
    """))
    #expect(tracks?.items == [Track(id: "v1", title: "Song", artist: "Band")])
    #expect(tracks?.nextPage == nil)

    #expect(YouTubeAPI.likesPlaylist(json(#"{"items":[{"contentDetails":{"relatedPlaylists":{"likes":"LL"}}}]}"#)) == "LL")
    let watch = YouTubeAPI.watchURL(track: Track(id: "v1", title: "", artist: ""),
                                    playlist: Playlist(id: "PL1", name: "", count: nil))
    #expect(watch.absoluteString == "https://www.youtube.com/watch?v=v1&list=PL1")
    #expect(YouTubeAPI.itemsURL(playlist: "PL1", pageToken: "T").absoluteString.contains("pageToken=T"))
}

// MARK: Browser

@Test func browserHomeOffersSystemAudioAndServices() {
    var view = MusicBrowserView()
    view.configured = [.spotify]
    let layout = MusicBrowser.layout(view, width: 30, rows: 6)
    #expect(text(layout.lines) == ["♪ Play from" + String(repeating: " ", count: 12) + "✕ close", "● System audio  listening",
                                   "○ Spotify  sign in", "○ YouTube  set up", "", ""])
    #expect(layout.actions == [.close, .close, .choose(.spotify), .choose(.youtube), nil, nil])
}

@Test func browserScrollsLongListsWithMoreMarkers() {
    var view = MusicBrowserView()
    view.screen = .playlists(.spotify)
    view.playlists = (1...10).map { Playlist(id: "\($0)", name: "List \($0)", count: nil) }
    let top = MusicBrowser.layout(view, width: 30, rows: 5)
    #expect(text(top.lines) == ["‹ Spotify", "List 1", "List 2", "List 3", "▾ 7 more"])
    #expect(top.actions.first == .back)
    #expect(top.actions.last == .scroll(3))

    view.scroll = 4
    let middle = MusicBrowser.layout(view, width: 30, rows: 6)
    #expect(text(middle.lines) == ["‹ Spotify", "▴ more", "List 5", "List 6", "List 7", "▾ 3 more"])
    #expect(middle.actions[1] == .scroll(-3))
    #expect(middle.actions[2] == .playlist(Playlist(id: "5", name: "List 5", count: nil)))
    #expect(MusicBrowser.maxScroll(count: 10, area: 5) == 7)
}

@Test func browserShowsTracksMessagesAndSetup() {
    var view = MusicBrowserView()
    let playlist = Playlist(id: "p", name: "Road trip", count: 2)
    view.screen = .tracks(.youtube, playlist)
    view.tracks = [Track(id: "v", title: "Song", artist: "Band")]
    let tracks = MusicBrowser.layout(view, width: 30, rows: 3)
    #expect(text(tracks.lines) == ["‹ YouTube › Road trip", "Song  Band", ""])
    #expect(tracks.actions[1] == .track(Track(id: "v", title: "Song", artist: "Band")))

    view.message = "Couldn't reach YouTube."
    #expect(text(MusicBrowser.layout(view, width: 30, rows: 3).lines) == ["‹ YouTube › Road trip", "Couldn't reach YouTube.", ""])

    view = MusicBrowserView()
    view.screen = .playlists(.spotify)
    view.loading = true
    #expect(text(MusicBrowser.layout(view, width: 30, rows: 2).lines) == ["‹ Spotify", "Loading…"])

    view.screen = .setup(.spotify)
    let setup = text(MusicBrowser.layout(view, width: 46, rows: 8).lines).joined(separator: " ")
    #expect(setup.contains("http://127.0.0.1:47823/callback") && setup.contains("--spotify-client-id"))

    view.screen = .signIn(.youtube)
    let signIn = MusicBrowser.layout(view, width: 46, rows: 4)
    #expect(text(signIn.lines)[1] == "Finish signing in to YouTube in your browser.")
    #expect(signIn.actions[2] == .back)
}
