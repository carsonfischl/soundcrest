import Foundation

/// Open-Meteo forecast (https://open-meteo.com), free and keyless.
public struct Forecast: Codable, Equatable, Sendable {
    public struct Current: Codable, Equatable, Sendable {
        public let temperature: Double
        public let feelsLike: Double
        public let humidity: Double
        public let code: Int
        public let wind: Double
        public let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m", feelsLike = "apparent_temperature"
            case humidity = "relative_humidity_2m", code = "weather_code"
            case wind = "wind_speed_10m", isDay = "is_day"
        }
    }

    public struct CurrentUnits: Codable, Equatable, Sendable {
        public let temperature: String
        public let wind: String

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m", wind = "wind_speed_10m"
        }
    }

    public struct Daily: Codable, Equatable, Sendable {
        public let time: [String]
        public let code: [Int]
        public let high: [Double]
        public let low: [Double]
        public let rainChance: [Double?]

        enum CodingKeys: String, CodingKey {
            case time, code = "weather_code", high = "temperature_2m_max", low = "temperature_2m_min"
            case rainChance = "precipitation_probability_max"
        }
    }

    public let current: Current
    public let currentUnits: CurrentUnits
    public let daily: Daily

    enum CodingKeys: String, CodingKey {
        case current, currentUnits = "current_units", daily
    }

    public static func url(latitude: Double, longitude: Double, imperial: Bool) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value:
                "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "daily", value:
                "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "4"),
        ] + (imperial ? [
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
        ] : [])
        return components.url!
    }
}

/// Open-Meteo place search, for `--weather-location CITY`.
public struct Place: Codable, Equatable, Sendable {
    public let name: String
    public let latitude: Double
    public let longitude: Double

    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    public static func searchURL(_ query: String) -> URL {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "1")]
        return components.url!
    }

    /// First match in a search response, or nil.
    public static func firstResult(in data: Data) -> Place? {
        struct Response: Decodable { let results: [Place]? }
        return (try? JSONDecoder().decode(Response.self, from: data))?.results?.first
    }
}

/// WMO weather codes as words and a small picture.
public enum Condition: Equatable, Sendable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, showers, thunder

    public init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67: self = .rain
        case 71...77, 85, 86: self = .snow
        case 80...82: self = .showers
        case 95...99: self = .thunder
        default: self = .cloudy
        }
    }

    public var title: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .showers: return "Showers"
        case .thunder: return "Thunderstorm"
        }
    }

    static let iconWidth = 11

    /// Three rows, each `iconWidth` columns.
    public func icon(isDay: Bool) -> [String] {
        let cloud = ["   .--.    ", " .(    ).  ", "(___.__)_) "]
        let rows: [String]
        switch self {
        case .clear:
            rows = isDay ? ["  \\  |  /  ", "  -- O --  ", "  /  |  \\  "]
                         : ["    .-.    ", "   (  (    ", "    `-'    "]
        case .partlyCloudy:
            rows = isDay ? [" \\ | .--.  ", "-- .(    ). ", " / (___.__)"]
                         : ["  .-..--.  ", " (  (    ). ", "  `(___.__)"]
        case .cloudy: rows = cloud
        case .fog: rows = [" _ - _ - _ ", "  - _ - _  ", " _ - _ - _ "]
        case .drizzle: rows = [cloud[1], cloud[2], "  ,  ,  ,  "]
        case .rain, .showers: rows = [cloud[1], cloud[2], " ' ' ' ' ' "]
        case .snow: rows = [cloud[1], cloud[2], "  *  *  *  "]
        case .thunder: rows = [cloud[1], cloud[2], "  ' /_ '   "]
        }
        return rows.map { Panel.truncated($0, to: Self.iconWidth).padding(toLength: Self.iconWidth, withPad: " ", startingAt: 0) }
    }
}

/// What the weather section shows.
public enum WeatherState: Equatable, Sendable {
    case waiting(String)
    case failed(String)
    case ready(place: String, forecast: Forecast, fetched: Date)
}

public enum WeatherPanel {
    public static func layout(_ state: WeatherState, width: Int, rows: Int, now: Date = Date()) -> [PanelLine] {
        guard rows > 0, width >= 8 else { return [] }
        switch state {
        case .waiting(let message):
            return Panel.wrap(message, width: width, maxLines: rows).map { [Span($0, .dim)] }
        case .failed(let message):
            return Panel.wrap(message, width: width, maxLines: rows).map { [Span($0)] }
        case .ready(let place, let forecast, let fetched):
            return ready(place: place, forecast: forecast, fetched: fetched, width: width, rows: rows, now: now)
        }
    }

    private static func ready(place: String, forecast: Forecast, fetched: Date, width: Int, rows: Int,
                              now: Date) -> [PanelLine] {
        let current = forecast.current
        let condition = Condition(code: current.code)
        let unit = forecast.currentUnits.temperature.replacingOccurrences(of: "°", with: "")
        let wind = forecast.currentUnits.wind.replacingOccurrences(of: "mp/h", with: "mph")

        let age = Int(now.timeIntervalSince(fetched) / 60)
        let header = Panel.clipped([Span(place, .accentBold(0)),
                                    Span(age >= 1 ? "  \(age)m ago" : "  now", .dim)], to: width)
        let details: [PanelLine] = [
            [Span(condition.title, .bold)],
            [Span("\(degrees(current.temperature))\(unit)", .accentBold(0.3)),
             Span("  feels \(degrees(current.feelsLike))", .dim)],
            [Span("\(Int(current.humidity.rounded()))% humid · \(Int(current.wind.rounded())) \(wind)", .dim)],
        ]
        let gap = 2
        let withIcon: [PanelLine] = width >= Condition.iconWidth + gap + 16
            ? zip(condition.icon(isDay: current.isDay == 1), details).map { icon, text in
                Panel.clipped([Span(icon, .accent(0.6)), Span(String(repeating: " ", count: gap))] + text, to: width)
            }
            : details.map { Panel.clipped($0, to: width) }

        let days = forecast.daily.time.indices.map { day(forecast.daily, $0, width: width) }
        return Panel.firstFitting([
            [header] + withIcon + [[]] + days,
            [header] + withIcon + days,
            [header] + withIcon + Array(days.prefix(2)),
            [header] + withIcon,
            details.prefix(2).map { Panel.clipped($0, to: width) },
            [Panel.clipped(details[1], to: width)],
        ], rows: rows)
    }

    /// `Sat    7°  11°  Rain 60%`.
    private static func day(_ daily: Forecast.Daily, _ index: Int, width: Int) -> PanelLine {
        let name = index == 0 ? "Today" : weekday(daily.time[index])
        let temps = "\(degrees(daily.low[index]))".leftPadded(4) + "\(degrees(daily.high[index]))".leftPadded(5)
        var line: PanelLine = [Span(name.padding(toLength: 5, withPad: " ", startingAt: 0), .bold),
                               Span(temps + "  "),
                               Span(Condition(code: daily.code[index]).title, .dim)]
        if let chance = daily.rainChance[safe: index] ?? nil, chance >= 20 {
            line.append(Span(" \(Int(chance))%", .accent(0.6)))
        }
        return Panel.clipped(line, to: width)
    }

    static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    private static func weekday(_ isoDate: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: isoDate) else { return isoDate }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}

extension String {
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
