import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A news outlet's RSS feed. `tag` is the short label shown beside headlines.
public struct NewsSource: Equatable, Sendable {
    public let id: String
    public let name: String
    public let tag: String
    public let url: URL

    public static let presets: [NewsSource] = [
        NewsSource(id: "bbc", name: "BBC News", tag: "BBC", url: "https://feeds.bbci.co.uk/news/rss.xml"),
        NewsSource(id: "nyt", name: "The New York Times", tag: "NYT",
                   url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml"),
        NewsSource(id: "npr", name: "NPR", tag: "NPR", url: "https://feeds.npr.org/1001/rss.xml"),
        NewsSource(id: "google", name: "Google News", tag: "GN",
                   url: "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en"),
        NewsSource(id: "guardian", name: "The Guardian", tag: "GDN", url: "https://www.theguardian.com/world/rss"),
        NewsSource(id: "wapo", name: "The Washington Post", tag: "WaPo",
                   url: "https://feeds.washingtonpost.com/rss/world"),
        NewsSource(id: "wsj", name: "The Wall Street Journal", tag: "WSJ",
                   url: "https://feeds.a.dj.com/rss/RSSWorldNews.xml"),
        NewsSource(id: "ft", name: "Financial Times", tag: "FT", url: "https://www.ft.com/rss/home"),
        NewsSource(id: "aljazeera", name: "Al Jazeera", tag: "AJ", url: "https://www.aljazeera.com/xml/rss/all.xml"),
    ]

    public static let defaults = ["bbc", "nyt", "npr", "google"].compactMap(preset(named:))

    public static func preset(named id: String) -> NewsSource? {
        presets.first { $0.id == id.lowercased() }
    }

    /// `bbc,nyt`. Nil when any name is unknown or the list is empty.
    public static func list(_ spec: String) -> [NewsSource]? {
        let sources = spec.split(separator: ",").map { preset(named: $0.trimmingCharacters(in: .whitespaces)) }
        guard !sources.isEmpty, !sources.contains(where: { $0 == nil }) else { return nil }
        return sources.compactMap { $0 }
    }

    private init(id: String, name: String, tag: String, url: StaticString) {
        self.id = id
        self.name = name
        self.tag = tag
        self.url = URL(string: "\(url)")!
    }
}

public struct Headline: Codable, Equatable, Sendable {
    public let title: String
    public let tag: String
    public let date: Date?
    public let link: String?
    /// The feed's description as plain text, when it says more than the title.
    public let summary: String?

    public init(title: String, tag: String, date: Date?, link: String?, summary: String? = nil) {
        self.title = title
        self.tag = tag
        self.date = date
        self.link = link
        self.summary = summary
    }

    /// The link when it is a web address safe to hand to `open`.
    public var webURL: URL? {
        guard let link, let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url
    }
}

/// Reads `<item>` titles, links and dates from an RSS 2.0 feed.
public final class RSSReader: NSObject, XMLParserDelegate {
    private let tag: String
    private var items: [Headline] = []
    private var field: String?
    private var text = ""
    private var current: [String: String] = [:]
    private var inItem = false

    public static func headlines(from data: Data, tag: String) -> [Headline] {
        let reader = RSSReader(tag: tag)
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.items
    }

    private init(tag: String) { self.tag = tag }

    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                       qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "item" {
            inItem = true
            current = [:]
        } else if inItem, ["title", "link", "pubDate", "description"].contains(name) {
            field = name
            text = ""
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { text += string }
    }

    public func parser(_ parser: XMLParser, foundCDATA block: Data) {
        if field != nil { text += String(decoding: block, as: UTF8.self) }
    }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                       qualifiedName: String?) {
        if name == "item" {
            inItem = false
            let title = HTMLText.plain(current["title"] ?? "")
            if !title.isEmpty {
                items.append(Headline(title: title, tag: tag, date: current["pubDate"].flatMap(Self.date(rfc822:)),
                                      link: current["link"], summary: Self.summary(current["description"], title: title)))
            }
        } else if name == field {
            current[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            field = nil
        }
    }

    /// Nil when the description is empty or only repeats the headline, as
    /// Google News descriptions do.
    static func summary(_ description: String?, title: String) -> String? {
        guard let description else { return nil }
        let text = HTMLText.plain(description)
        let key = { (value: String) in value.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard !text.isEmpty, !key(text).hasPrefix(key(String(title.prefix(40)))) else { return nil }
        return text
    }

    static func date(rfc822 text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

public enum NewsPanel {
    /// Newest first within each source, taking turns between sources so no
    /// single outlet fills the panel.
    public static func merge(_ feeds: [[Headline]], perSource: Int = 10) -> [Headline] {
        let sorted = feeds.map { feed in
            Array(feed.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(perSource))
        }
        var merged: [Headline] = []
        var seen = Set<String>()
        for index in 0..<(sorted.map(\.count).max() ?? 0) {
            for feed in sorted where index < feed.count && seen.insert(feed[index].title.lowercased()).inserted {
                merged.append(feed[index])
            }
        }
        return merged
    }

    public struct Page: Equatable {
        public let lines: [PanelLine]
        /// For each line, the index in `headlines` of the article it belongs to.
        public let owners: [Int?]
        public let shown: Int
    }

    /// Articles from `start`: a headline of up to two lines beside its source
    /// tag, up to `summaryLines` of description under it, and a blank line
    /// between articles. Summaries are dropped before articles when short of room.
    public static func layout(_ headlines: [Headline], start: Int, width: Int, rows: Int,
                              summaryLines: Int = 2) -> Page {
        guard rows > 0, width >= 12, !headlines.isEmpty else { return Page(lines: [], owners: [], shown: 0) }
        let tagWidth = 4
        let indent = String(repeating: " ", count: tagWidth + 1)
        var lines: [PanelLine] = []
        var owners: [Int?] = []
        var shown = 0
        while shown < headlines.count {
            let index = (start + shown) % headlines.count
            let headline = headlines[index]
            let title = Panel.wrap(headline.title, width: width - tagWidth - 1, maxLines: 2)
            let summary = Panel.wrap(headline.summary ?? "", width: width - tagWidth - 1, maxLines: summaryLines)
            let gap = lines.isEmpty ? 0 : 1
            let room = rows - lines.count - gap
            guard !title.isEmpty, title.count <= room else { break }

            if gap > 0 {
                lines.append([])
                owners.append(nil)
            }
            let tag = Panel.truncated(headline.tag, to: tagWidth).padding(toLength: tagWidth, withPad: " ", startingAt: 0)
            for (number, text) in title.enumerated() {
                lines.append([number == 0 ? Span(tag + " ", .accentBold(shade(headline.tag))) : Span(indent),
                              Span(text, .bold)])
            }
            for text in summary.prefix(room - title.count) {
                lines.append([Span(indent), Span(text, .dim)])
            }
            owners += Array(repeating: index, count: lines.count - owners.count)
            shown += 1
        }
        return Page(lines: lines, owners: owners, shown: shown)
    }

    /// A steady colour per outlet, spread across the palette.
    static func shade(_ tag: String) -> Float {
        let index = NewsSource.presets.firstIndex { $0.tag == tag } ?? 0
        return Float(index) / Float(max(NewsSource.presets.count - 1, 1))
    }
}

/// What the news section shows.
public enum NewsState: Equatable, Sendable {
    case waiting(String)
    case failed(String)
    case ready([Headline], fetched: Date)
}

/// Plain text from the bits of HTML that feeds put in titles and descriptions.
public enum HTMLText {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "mdash": "—", "ndash": "–", "hellip": "…",
    ]

    public static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        var out = ""
        while let amp = text.firstIndex(of: "&") {
            out += text[..<amp]
            let rest = text[text.index(after: amp)...]
            if let semi = rest.prefix(10).firstIndex(of: ";"), let decoded = entity(String(rest[..<semi])) {
                out += decoded
                text = String(rest[rest.index(after: semi)...])
            } else {
                out += "&"
                text = String(rest)
            }
        }
        out += text
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func entity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first.map { $0 == "x" || $0 == "X" } == true
                ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[name]
    }
}
