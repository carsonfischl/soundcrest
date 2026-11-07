#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
/// loopback port. Runs on the pane's `MainLoop`.
final class SignIn {
    private var server: LoopbackServer?
    private var verifier = ""
    private var state = ""
    private var completion: ((Result<Tokens, Failure>) -> Void)?

    var isRunning: Bool { server != nil }

    func start(_ service: MusicService, credentials: MusicCredentials,
               _ completion: @escaping (Result<Tokens, Failure>) -> Void) {
        cancel()
        verifier = Self.random(48)
        state = Self.random(16)
        self.completion = completion

        guard let server = LoopbackServer(port: MusicAuth.port, { [weak self] requestLine, reply in
            self?.handle(requestLine, reply: reply, service: service, credentials: credentials)
        }) else {
            return finish(.failure(Failure("Port \(MusicAuth.port) is busy. Close other sign-ins and try again.")))
        }
        self.server = server

        let challenge = Self.base64URL(Data(SHA256Digest.hash(Array(verifier.utf8))))
        openInBrowser(MusicAuth.authorizeURL(service, clientID: credentials.clientID, challenge: challenge, state: state))
    }

    func cancel() {
        server?.stop()
        server = nil
        completion = nil
    }

    private func handle(_ requestLine: String, reply: (String, String) -> Void, service: MusicService,
                        credentials: MusicCredentials) {
        guard let callback = MusicAuth.callback(requestLine: requestLine) else {
            return reply("404 Not Found", "Not found")
        }
        guard callback.state == state, let code = callback.code else {
            reply("200 OK", "Sign-in didn't finish. You can close this tab.")
            return finish(.failure(Failure(callback.error == "access_denied"
                ? "Sign-in cancelled." : "Sign-in failed: \(callback.error ?? "unexpected reply").")))
        }
        reply("200 OK", "Signed in to \(service.title). You can close this tab and go back to your terminal.")
        server?.stop()
        server = nil

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

    private func finish(_ result: Result<Tokens, Failure>) {
        server?.stop()
        server = nil
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    private static func random(_ bytes: Int) -> String {
        base64URL(Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Opens a web page with `open` on macOS or `xdg-open` on Linux.
func openInBrowser(_ url: URL) {
    let process = Process()
    #if os(macOS)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    #else
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["xdg-open", url.absoluteString]
    #endif
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
}

/// A one-purpose HTTP listener on 127.0.0.1 for the sign-in redirect. It
/// accepts on a background thread and hands each request line to `handler` on
/// the `MainLoop`, with a way to send back a small HTML page.
final class LoopbackServer: @unchecked Sendable {
    typealias Handler = (_ requestLine: String, _ reply: (_ status: String, _ message: String) -> Void) -> Void

    private let socket: Int32
    private let lock = NSLock()
    private var stopped = false

    init?(port: UInt16, _ handler: @escaping Handler) {
        #if canImport(Darwin)
        socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        #else
        socket = Glibc.socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard socket >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(socket, 4) == 0 else {
            close(socket)
            return nil
        }
        let thread = Thread { [self] in acceptLoop(handler) }
        thread.name = "soundcrest sign-in"
        thread.start()
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        shutdown(socket, Int32(SHUT_RDWR))
        close(socket)
    }

    private func acceptLoop(_ handler: @escaping Handler) {
        while true {
            let client = accept(socket, nil, nil)
            guard client >= 0 else { return }  // closed by stop()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let count = read(client, &buffer, buffer.count)
            let request = count > 0 ? String(decoding: buffer[..<count], as: UTF8.self) : ""
            let requestLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
            MainLoop.post {
                var answered = false
                handler(requestLine) { status, message in
                    answered = true
                    Self.respond(client, status: status, message: message)
                }
                if !answered { Self.respond(client, status: "404 Not Found", message: "Not found") }
            }
        }
    }

    private static func respond(_ client: Int32, status: String, message: String) {
        let body = "<!doctype html><meta charset=utf-8><title>soundcrest</title>"
            + "<body style=\"font:16px system-ui,sans-serif;margin:3em\">\(message)</body>"
        let response = Array(("HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body).utf8)
        _ = response.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
        close(client)
    }
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
