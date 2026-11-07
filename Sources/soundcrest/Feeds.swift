#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import WaveCore

/// Results shared by every pane through ~/Library/Caches, so a new window shows
/// data at once and only one window refetches when it goes stale.
enum FeedCache {
    private static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("local.soundcrest", isDirectory: true)

    static func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

/// HTTP requests whose completions arrive on the pane's `MainLoop`.
enum HTTP {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": "soundcrest"]
        return URLSession(configuration: configuration)
    }()

    static func get(_ url: URL, _ completion: @escaping (Data?) -> Void) {
        send(URLRequest(url: url)) { data, status in completion((200..<300).contains(status) ? data : nil) }
    }

    /// Any request; `status` is 0 when there was no response at all.
    static func send(_ request: URLRequest, _ completion: @escaping (_ data: Data?, _ status: Int) -> Void) {
        session.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            MainLoop.post { completion(data, status) }
        }.resume()
    }
}

/// Weather for the pane. Main thread only.
final class WeatherFeed {
    private struct Cached: Codable {
        let query: String?
        let imperial: Bool
        let place: String
        let forecast: Forecast
        let fetched: Date
    }

    private static let file = "weather.json"
    private static let freshFor: TimeInterval = 15 * 60
    private static let retryAfter: TimeInterval = 5 * 60
    /// How long a found position, or a failure to find one, is trusted.
    private static let positionFreshFor: TimeInterval = 30 * 60
    private static let failureFreshFor: TimeInterval = 5 * 60
    /// The helper gives up after two minutes; don't start a second meanwhile.
    private static let helperWait: TimeInterval = 150

    private(set) var state = WeatherState.waiting("Finding your location… If macOS asks, allow soundcrest.")
    private var busy = false
    private var nextAttempt = Date.distantPast
    private var lastQuery: String??
    private var helperLaunched = Date.distantPast

    /// `query` is a place to look up, or nil for Location Services.
    func update(query: String?) {
        let imperial = Locale.current.measurementSystem == .us
        if lastQuery != .some(query) {
            lastQuery = .some(query)
            nextAttempt = .distantPast
        }
        let cached = FeedCache.read(Self.file, as: Cached.self).flatMap {
            $0.query == query && $0.imperial == imperial ? $0 : nil
        }
        if let cached {
            state = .ready(place: cached.place, forecast: cached.forecast, fetched: cached.fetched)
        } else if case .ready = state {
            state = .waiting(query.map { "Looking up \($0)…" } ?? "Finding your location…")
        }
        let stale = cached.map { Date().timeIntervalSince($0.fetched) >= Self.freshFor } ?? true

        guard let query else {
            guard let outcome = position() else { return }
            switch outcome {
            case .failure(let failure):
                if cached == nil { state = .failed(failure.message) }
            case .success(let place):
                if stale || cached?.place != place.name { fetch(place, query: nil, imperial: imperial, cached: cached) }
            }
            return
        }
        guard stale, !busy, Date() >= nextAttempt else { return }
        busy = true
        nextAttempt = Date().addingTimeInterval(Self.retryAfter)
        HTTP.get(Place.searchURL(query)) { [self] data in
            busy = false
            if let place = data.flatMap(Place.firstResult) {
                nextAttempt = .distantPast
                fetch(place, query: query, imperial: imperial, cached: cached)
            } else if cached == nil {
                state = .failed(data == nil
                    ? "Couldn't reach the place search. Retrying in a few minutes."
                    : "No place called “\(query)”. Try soundcrest --weather-location with a nearby city.")
            }
        }
    }

    /// The helper's latest answer, starting it again when the answer is old.
    /// Nil while there is no answer yet.
    private func position() -> Result<Place, Failure>? {
        #if !os(macOS)
        return .failure(Failure("Pick a place for the weather: soundcrest --weather-location CITY"))
        #else
        let outcome = FeedCache.read(LocationHelper.file, as: LocationApp.Outcome.self)
        let age = outcome.map { Date().timeIntervalSince($0.finished) } ?? .infinity
        let trustedFor = outcome?.place == nil ? Self.failureFreshFor : Self.positionFreshFor
        if age >= trustedFor, Date().timeIntervalSince(helperLaunched) >= Self.helperWait {
            helperLaunched = Date()
            LocationHelper.launch()
        }
        if let place = outcome?.place { return .success(place) }
        if let failure = outcome?.failure { return .failure(Failure(failure)) }
        return nil
        #endif
    }

    private func fetch(_ place: Place, query: String?, imperial: Bool, cached: Cached?) {
        guard !busy, Date() >= nextAttempt else { return }
        busy = true
        nextAttempt = Date().addingTimeInterval(Self.retryAfter)
        let hadForecast = cached != nil
        HTTP.get(Forecast.url(latitude: place.latitude, longitude: place.longitude, imperial: imperial)) { [self] data in
            busy = false
            guard let data, let forecast = try? JSONDecoder().decode(Forecast.self, from: data) else {
                if !hadForecast { state = .failed("Couldn't reach Open-Meteo. Retrying in a few minutes.") }
                return
            }
            let fresh = Cached(query: query, imperial: imperial, place: place.name, forecast: forecast, fetched: Date())
            FeedCache.write(fresh, Self.file)
            state = .ready(place: fresh.place, forecast: forecast, fetched: fresh.fetched)
        }
    }
}

struct Failure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

#if os(macOS)
/// One-shot Core Location lookups. Main thread only.
final class Locator: NSObject, CLLocationManagerDelegate {
    private static let denied = Failure(
        "Location access is off. Allow it in System Settings > Privacy & Security > Location Services, "
            + "or pick a place: soundcrest --weather-location CITY")

    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, Failure>) -> Void)?
    private var requested = false
    private var attempt = 0
    private let timeout: TimeInterval

    init(timeout: TimeInterval) {
        self.timeout = timeout
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func locate(_ completion: @escaping (Result<CLLocation, Failure>) -> Void) {
        self.completion = completion
        requested = false
        attempt += 1
        let current = attempt
        manager.delegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.attempt == current else { return }
            self.finish(.failure(Failure(
                "No answer from Location Services. Allow soundcrest in System Settings > Privacy & Security > "
                    + "Location Services, or pick a place: soundcrest --weather-location CITY")))
        }
        proceed()
    }

    private func proceed() {
        guard completion != nil, !requested else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(Self.denied))
        default:
            requested = true
            manager.requestLocation()
        }
    }

    private func finish(_ result: Result<CLLocation, Failure>) {
        guard let completion else { return }
        self.completion = nil
        completion(result)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { proceed() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last { finish(.success(location)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        finish(.failure(code == .denied ? Self.denied : Failure("Couldn't find your location. Retrying soon.")))
    }

    /// Town or city from Apple's geocoder, or a fallback when it has none.
    static func name(of location: CLLocation, _ completion: @escaping (String) -> Void) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let mark = placemarks?.first
            completion(mark?.locality ?? mark?.subAdministrativeArea ?? mark?.administrativeArea ?? "Your location")
        }
    }
}
#endif

/// Headlines for the pane. Main thread only.
final class NewsFeed {
    private struct Cached: Codable {
        let sources: [String]
        let headlines: [Headline]
        let fetched: Date
    }

    private static let file = "news.json"
    private static let freshFor: TimeInterval = 10 * 60
    private static let retryAfter: TimeInterval = 2 * 60

    private(set) var state = NewsState.waiting("Loading headlines…")
    private var busy = false
    private var nextAttempt = Date.distantPast
    private var lastSources: [String] = []

    func update(sources: [NewsSource]) {
        let ids = sources.map(\.id)
        if ids != lastSources {
            lastSources = ids
            nextAttempt = .distantPast
        }
        let cached = FeedCache.read(Self.file, as: Cached.self).flatMap { $0.sources == ids ? $0 : nil }
        if let cached {
            if state != .ready(cached.headlines, fetched: cached.fetched) {
                state = .ready(cached.headlines, fetched: cached.fetched)
            }
            guard Date().timeIntervalSince(cached.fetched) >= Self.freshFor else { return }
        } else if case .ready = state {
            state = .waiting("Loading headlines…")
        }
        guard !busy, Date() >= nextAttempt else { return }
        busy = true
        nextAttempt = Date().addingTimeInterval(Self.retryAfter)

        var feeds = [[Headline]](repeating: [], count: sources.count)
        var pending = sources.count
        for (index, source) in sources.enumerated() {
            HTTP.get(source.url) { [self] data in
                if let data { feeds[index] = RSSReader.headlines(from: data, tag: source.tag) }
                pending -= 1
                guard pending == 0 else { return }
                busy = false
                let headlines = NewsPanel.merge(feeds)
                guard !headlines.isEmpty else {
                    if cached == nil { state = .failed("Couldn't load headlines. Retrying in a few minutes.") }
                    return
                }
                let fresh = Cached(sources: ids, headlines: headlines, fetched: Date())
                FeedCache.write(fresh, Self.file)
                state = .ready(headlines, fetched: fresh.fetched)
            }
        }
    }
}
