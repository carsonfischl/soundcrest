import CryptoKit
import Foundation
import Network
import WaveCore

/// Sign-in tokens, kept in a file only you can read so every pane window and
/// every rebuild of soundcrest can use them without Keychain prompts.
enum TokenStore {
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("soundcrest/tokens.json")
    }

    static func load(_ service: MusicService) -> Tokens? { all()[service.rawValue] }

    static func save(_ tokens: Tokens?, for service: MusicService) {
        var stored = all()
        stored[service.rawValue] = tokens
        guard let data = try? JSONEncoder().encode(stored) else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: [.atomic])
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private static func all() -> [String: Tokens] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: Tokens].self, from: data)) ?? [:]
    }
}

/// Signs in through the browser with OAuth PKCE, catching the redirect on a
/// loopback port. Main thread only.
final class SignIn {
    private var listener: NWListener?
    private var verifier = ""
    private var state = ""
    private var completion: ((Result<Tokens, Failure>) -> Void)?

    var isRunning: Bool { listener != nil }

    func start(_ service: MusicService, credentials: MusicCredentials,
               _ completion: @escaping (Result<Tokens, Failure>) -> Void) {
        cancel()
        verifier = Self.random(48)
        state = Self.random(16)
        self.completion = completion

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: MusicAuth.port)!)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else {
            return finish(.failure(Failure("Couldn't listen on port \(MusicAuth.port). Is another sign-in open?")))
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.finish(.failure(Failure("Port \(MusicAuth.port) is busy. Close other sign-ins and try again.")))
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection, service: service, credentials: credentials)
        }
        listener.start(queue: .main)

        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        openInBrowser(MusicAuth.authorizeURL(service, clientID: credentials.clientID, challenge: challenge, state: state))
    }

    func cancel() {
        listener?.cancel()
        listener = nil
        completion = nil
    }

    private func handle(_ connection: NWConnection, service: MusicService, credentials: MusicCredentials) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?
                .split(separator: "\r\n").first.map(String.init) ?? ""
            guard let callback = MusicAuth.callback(requestLine: requestLine) else {
                return Self.reply(connection, "Not found", status: "404 Not Found")
            }
            guard callback.state == state, let code = callback.code else {
                Self.reply(connection, "Sign-in didn't finish. You can close this tab.")
                return finish(.failure(Failure(callback.error == "access_denied"
                    ? "Sign-in cancelled." : "Sign-in failed: \(callback.error ?? "unexpected reply").")))
            }
            Self.reply(connection, "Signed in to \(service.title). You can close this tab and go back to Terminal.")
            listener?.cancel()
            listener = nil

            var request = URLRequest(url: MusicAuth.tokenURL(service))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = MusicAuth.formBody(MusicAuth.exchangeForm(code: code, verifier: verifier,
                                                                         credentials: credentials))
            HTTP.send(request) { [weak self] data, status in
                guard (200..<300).contains(status), let tokens = data.flatMap({ Tokens.decode($0) }) else {
                    self?.finish(.failure(Failure("\(service.title) refused the sign-in (HTTP \(status)). "
                        + "Check the client ID and redirect URI \(MusicAuth.redirect).")))
                    return
                }
                self?.finish(.success(tokens))
            }
        }
    }

    private func finish(_ result: Result<Tokens, Failure>) {
        listener?.cancel()
        listener = nil
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    private static func reply(_ connection: NWConnection, _ message: String, status: String = "200 OK") {
        let body = "<!doctype html><meta charset=utf-8><title>soundcrest</title>"
            + "<body style=\"font:16px -apple-system;margin:3em\">\(message)</body>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func random(_ bytes: Int) -> String {
        base64URL(Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

func openInBrowser(_ url: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    try? process.run()
}

/// Authorized API calls, refreshing the access token when it runs out.
/// Main thread only.
enum MusicAPI {
    static func get(_ url: URL, _ service: MusicService, _ completion: @escaping (Result<Data, Failure>) -> Void) {
        withToken(service) { result in
            switch result {
            case .failure(let failure): completion(.failure(failure))
            case .success(let token):
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                HTTP.send(request) { data, status in
                    switch status {
                    case 200..<300: completion(data.map { .success($0) } ?? .failure(Failure("Empty reply.")))
                    case 401:
                        TokenStore.save(nil, for: service)
                        completion(.failure(Failure("\(service.title) signed you out. Click back and sign in again.")))
                    case 403:
                        completion(.failure(Failure("\(service.title) won't share this (HTTP 403). "
                            + (service == .spotify ? "Development-mode apps only see playlists you own or follow, "
                                + "and your account must be added under User Management." : "Check the API is enabled."))))
                    case 0: completion(.failure(Failure("Couldn't reach \(service.title).")))
                    default: completion(.failure(Failure("\(service.title) replied HTTP \(status).")))
                    }
                }
            }
        }
    }

    private static func withToken(_ service: MusicService, _ completion: @escaping (Result<String, Failure>) -> Void) {
        guard let tokens = TokenStore.load(service) else { return completion(.failure(Failure("Not signed in."))) }
        if tokens.expires > Date() { return completion(.success(tokens.access)) }
        guard let refresh = tokens.refresh, let credentials = MusicCredentials.stored(service, in: .standard) else {
            TokenStore.save(nil, for: service)
            return completion(.failure(Failure("Sign-in expired. Click back and sign in again.")))
        }
        var request = URLRequest(url: MusicAuth.tokenURL(service))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = MusicAuth.formBody(MusicAuth.refreshForm(refreshToken: refresh, credentials: credentials))
        HTTP.send(request) { data, status in
            guard (200..<300).contains(status), let fresh = data.flatMap({ Tokens.decode($0, previous: refresh) }) else {
                if status == 400 || status == 401 { TokenStore.save(nil, for: service) }
                return completion(.failure(Failure(status == 0 ? "Couldn't reach \(service.title)."
                                                               : "Sign-in expired. Click back and sign in again.")))
            }
            TokenStore.save(fresh, for: service)
            completion(.success(fresh.access))
        }
    }

    /// Follows `next` pages up to `limit` items.
    static func spotifyPages<Item>(_ url: URL, limit: Int = 300, decode: @escaping (Data) -> WaveCore.Page<Item>?,
                                   _ completion: @escaping (Result<[Item], Failure>) -> Void) {
        get(url, .spotify) { result in
            switch result {
            case .failure(let failure): completion(.failure(failure))
            case .success(let data):
                guard let page = decode(data) else { return completion(.failure(Failure("Unexpected reply from Spotify."))) }
                guard let next = page.next, limit > page.items.count else { return completion(.success(page.items)) }
                spotifyPages(next, limit: limit - page.items.count, decode: decode) { rest in
                    completion(.success(page.items + ((try? rest.get()) ?? [])))
                }
            }
        }
    }

    static func youtubePages<Item>(_ url: @escaping (String?) -> URL, token: String? = nil, limit: Int = 300,
                                   decode: @escaping (Data) -> (items: [Item], nextPage: String?)?,
                                   _ completion: @escaping (Result<[Item], Failure>) -> Void) {
        get(url(token), .youtube) { result in
            switch result {
            case .failure(let failure): completion(.failure(failure))
            case .success(let data):
                guard let page = decode(data) else { return completion(.failure(Failure("Unexpected reply from YouTube."))) }
                guard let next = page.nextPage, limit > page.items.count else { return completion(.success(page.items)) }
                youtubePages(url, token: next, limit: limit - page.items.count, decode: decode) { rest in
                    completion(.success(page.items + ((try? rest.get()) ?? [])))
                }
            }
        }
    }
}
