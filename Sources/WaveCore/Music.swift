import Foundation

/// A streaming service whose playlists the pane can browse. Songs never play
/// inside soundcrest: Spotify plays them in its desktop app and YouTube in the
/// browser, so they reach the waveform as ordinary system audio.
public enum MusicService: String, CaseIterable, Codable, Sendable {
    case spotify, youtube

    public var title: String { self == .spotify ? "Spotify" : "YouTube" }
}

public struct Playlist: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let count: Int?

    public init(id: String, name: String, count: Int?) {
        self.id = id
        self.name = name
        self.count = count
    }

    /// Spotify's saved tracks and YouTube's liked videos, which the APIs keep
    /// apart from ordinary playlists.
    public static let likedID = "liked"
}

public struct Track: Codable, Equatable, Sendable {
    /// `spotify:track:…` for Spotify, a video ID for YouTube.
    public let id: String
    public let title: String
    public let artist: String

    public init(id: String, title: String, artist: String) {
        self.id = id
        self.title = title
        self.artist = artist
    }
}

/// A page of results and the URL of the next page, if any.
public struct Page<Item: Equatable>: Equatable {
    public let items: [Item]
    public let next: URL?
}

// MARK: - OAuth

public enum MusicAuth {
    /// Loopback address the sign-in page sends you back to. Spotify needs it
    /// registered exactly; Google accepts any loopback port for desktop apps.
    public static let port: UInt16 = 47823
    public static let redirect = "http://127.0.0.1:\(port)/callback"

    public static func authorizeURL(_ service: MusicService, clientID: String, challenge: String,
                                    state: String) -> URL {
        var components: URLComponents
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
        ]
        switch service {
        case .spotify:
            components = URLComponents(string: "https://accounts.spotify.com/authorize")!
            items.append(URLQueryItem(name: "scope",
                                      value: "playlist-read-private playlist-read-collaborative user-library-read"))
        case .youtube:
            components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            items += [
                URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/youtube.readonly"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
            ]
        }
        components.queryItems = items
        return components.url!
    }

    public static func tokenURL(_ service: MusicService) -> URL {
        URL(string: service == .spotify ? "https://accounts.spotify.com/api/token"
                                        : "https://oauth2.googleapis.com/token")!
    }

    /// Form fields to trade a sign-in code for tokens.
    public static func exchangeForm(code: String, verifier: String, credentials: MusicCredentials) -> [String: String] {
        var form = ["grant_type": "authorization_code", "code": code, "redirect_uri": redirect,
                    "client_id": credentials.clientID, "code_verifier": verifier]
        if let secret = credentials.clientSecret { form["client_secret"] = secret }
        return form
    }

    public static func refreshForm(refreshToken: String, credentials: MusicCredentials) -> [String: String] {
        var form = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": credentials.clientID]
        if let secret = credentials.clientSecret { form["client_secret"] = secret }
        return form
    }

    public static func formBody(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }

    /// Code and state from the request line the browser sends back, e.g.
    /// `GET /callback?code=abc&state=xyz HTTP/1.1`. Nil when it carries neither.
    public static func callback(requestLine: String) -> (code: String?, state: String?, error: String?)? {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let items = URLComponents(string: "http://127.0.0.1" + parts[1])?.queryItems else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard value("code") != nil || value("error") != nil else { return nil }
        return (value("code"), value("state"), value("error"))
    }
}

/// App credentials you register with each service.
public struct MusicCredentials: Equatable, Sendable {
    public let clientID: String
    /// Google desktop clients come with a secret that isn't confidential but is
    /// still required. Spotify uses PKCE alone.
    public let clientSecret: String?

    private static func idKey(_ service: MusicService) -> String { service.rawValue + "ClientID" }
    private static func secretKey(_ service: MusicService) -> String { service.rawValue + "ClientSecret" }

    public init(clientID: String, clientSecret: String?) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public static func stored(_ service: MusicService, in store: UserDefaults) -> MusicCredentials? {
        guard let id = store.string(forKey: idKey(service)), !id.isEmpty else { return nil }
        let secret = store.string(forKey: secretKey(service))
        if service == .youtube, secret?.isEmpty ?? true { return nil }
        return MusicCredentials(clientID: id, clientSecret: secret)
    }

    public func save(_ service: MusicService, in store: UserDefaults) {
        store.set(clientID, forKey: Self.idKey(service))
        if let clientSecret { store.set(clientSecret, forKey: Self.secretKey(service)) }
        else { store.removeObject(forKey: Self.secretKey(service)) }
    }
}

public struct Tokens: Codable, Equatable, Sendable {
    public var access: String
    public var refresh: String?
    public var expires: Date

    public init(access: String, refresh: String?, expires: Date) {
        self.access = access
        self.refresh = refresh
        self.expires = expires
    }

    /// Reads a token response. A refresh response may leave out the refresh
    /// token, in which case `previous` keeps the old one.
    public static func decode(_ data: Data, previous: String? = nil, now: Date = Date()) -> Tokens? {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return Tokens(access: response.access_token, refresh: response.refresh_token ?? previous,
                      expires: now.addingTimeInterval((response.expires_in ?? 3600) - 60))
    }
}

// MARK: - API responses

public enum SpotifyAPI {
    public static let playlistsURL = URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")!
    public static let likedURL = URL(string: "https://api.spotify.com/v1/me/tracks?limit=50")!

    public static func itemsURL(playlist id: String) -> URL {
        id == Playlist.likedID ? likedURL
            : URL(string: "https://api.spotify.com/v1/playlists/\(id)/items?limit=50")!
    }

    public static func playlists(_ data: Data) -> Page<Playlist>? {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Count: Decodable { let total: Int? }
                let id: String
                let name: String?
                let items: Count?
                let tracks: Count?
            }
            let items: [Item?]
            let next: URL?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let playlists = response.items.compactMap { $0 }.map {
            Playlist(id: $0.id, name: $0.name ?? "Untitled", count: ($0.items ?? $0.tracks)?.total)
        }
        return Page(items: playlists, next: response.next)
    }

    /// Tracks from playlist items or saved tracks, skipping podcast episodes
    /// and local files.
    public static func tracks(_ data: Data) -> Page<Track>? {
        struct Response: Decodable {
            struct Entry: Decodable {
                struct Item: Decodable {
                    struct Artist: Decodable { let name: String }
                    let uri: String?
                    let name: String?
                    let type: String?
                    let artists: [Artist]?
                    let is_local: Bool?
                }
                let item: Item?
                let track: Item?
            }
            let items: [Entry]
            let next: URL?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let tracks = response.items.compactMap { entry -> Track? in
            guard let item = entry.item ?? entry.track, item.type ?? "track" == "track", item.is_local != true,
                  let uri = item.uri, uri.hasPrefix("spotify:track:"), let name = item.name else { return nil }
            return Track(id: uri, title: name, artist: (item.artists ?? []).map(\.name).joined(separator: ", "))
        }
        return Page(items: tracks, next: response.next)
    }

    /// AppleScript for the Spotify desktop app.
    public static func playScript(track: Track, playlist: Playlist) -> String {
        let quoted = { (text: String) in "\"" + text.replacingOccurrences(of: "\"", with: "") + "\"" }
        guard playlist.id != Playlist.likedID else {
            return "tell application \"Spotify\" to play track \(quoted(track.id))"
        }
        return "tell application \"Spotify\" to play track \(quoted(track.id)) in context "
            + quoted("spotify:playlist:\(playlist.id)")
    }
}

public enum YouTubeAPI {
    private static let base = "https://www.googleapis.com/youtube/v3/"

    public static func playlistsURL(pageToken: String? = nil) -> URL {
        url("playlists", ["part": "snippet,contentDetails", "mine": "true", "maxResults": "50"], pageToken)
    }

    public static let channelURL = url("channels", ["part": "contentDetails", "mine": "true"], nil)

    public static func itemsURL(playlist id: String, pageToken: String? = nil) -> URL {
        url("playlistItems", ["part": "snippet", "playlistId": id, "maxResults": "50"], pageToken)
    }

    private static func url(_ path: String, _ query: [String: String], _ pageToken: String?) -> URL {
        var components = URLComponents(string: base + path)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
        return components.url!
    }

    /// The ID of the signed-in channel's liked-videos playlist.
    public static func likesPlaylist(_ data: Data) -> String? {
        struct Response: Decodable {
            struct Channel: Decodable {
                struct Details: Decodable {
                    struct Related: Decodable { let likes: String? }
                    let relatedPlaylists: Related
                }
                let contentDetails: Details
            }
            let items: [Channel]?
        }
        return (try? JSONDecoder().decode(Response.self, from: data))?.items?.first?.contentDetails
            .relatedPlaylists.likes
    }

    public static func playlists(_ data: Data) -> (items: [Playlist], nextPage: String?)? {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Snippet: Decodable { let title: String }
                struct Details: Decodable { let itemCount: Int? }
                let id: String
                let snippet: Snippet
                let contentDetails: Details?
            }
            let items: [Item]
            let nextPageToken: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return (response.items.map { Playlist(id: $0.id, name: $0.snippet.title, count: $0.contentDetails?.itemCount) },
                response.nextPageToken)
    }

    public static func tracks(_ data: Data) -> (items: [Track], nextPage: String?)? {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Snippet: Decodable {
                    struct Resource: Decodable { let videoId: String? }
                    let title: String
                    let videoOwnerChannelTitle: String?
                    let resourceId: Resource
                }
                let snippet: Snippet
            }
            let items: [Item]
            let nextPageToken: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        // Deleted and private videos keep a slot with no channel.
        let tracks = response.items.compactMap { item -> Track? in
            guard let id = item.snippet.resourceId.videoId, let channel = item.snippet.videoOwnerChannelTitle else {
                return nil
            }
            return Track(id: id, title: item.snippet.title,
                         artist: channel.hasSuffix(" - Topic") ? String(channel.dropLast(8)) : channel)
        }
        return (tracks, response.nextPageToken)
    }

    public static func watchURL(track: Track, playlist: Playlist) -> URL {
        var components = URLComponents(string: "https://www.youtube.com/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: track.id), URLQueryItem(name: "list", value: playlist.id)]
        return components.url!
    }
}
