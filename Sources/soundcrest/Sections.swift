import Foundation
import WaveCore

/// The info, weather and news views under the pane's waveform, one at a time.
/// Main thread only.
final class Sections {
    private static let infoRefresh: TimeInterval = 5
    private static let newsPage: TimeInterval = 20

    private var settings = PaneSettings.stored(in: .standard)
    private var selected: PaneSection?
    private let info = SystemInfo()
    private var fields: [InfoPanel.Field] = []
    private var fieldsRead = Date.distantPast
    private let weather = WeatherFeed()
    private let news = NewsFeed()
    private var newsStart = 0
    private var newsShown = 0
    private var newsTurned = Date()
    /// What a click on each pane row does, from the last `render`.
    private var hits: [Int: Hit] = [:]

    private enum Hit {
        case link(URL)
        case tabs([(columns: ClosedRange<Int>, section: PaneSection)])
    }

    init() {
        selected = settings.selected
        refresh()
    }

    /// Re-reads settings and lets feeds refetch. Call about once a second.
    func refresh() {
        settings = PaneSettings.stored(in: .standard)
        if selected.map({ !settings.enabled.contains($0) }) ?? true { selected = settings.enabled.first }

        switch selected {
        case .info?:
            if Date().timeIntervalSince(fieldsRead) >= Self.infoRefresh {
                fields = info.fields()
                fieldsRead = Date()
            }
        case .weather?:
            weather.update(query: settings.weatherLocation)
        case .news?:
            news.update(sources: settings.newsSources)
            if Date().timeIntervalSince(newsTurned) >= Self.newsPage {
                newsStart += max(newsShown, 1)
                newsTurned = Date()
            }
        case nil:
            break
        }
    }

    /// Moves to the next enabled section and remembers it for new windows.
    func cycle() {
        var next = settings
        next.selected = selected
        if let section = next.nextSection { select(section) }
    }

    private func select(_ section: PaneSection) {
        guard section != selected else { return }
        selected = section
        PaneSettings.select(section, in: .standard)
        newsTurned = Date()
        refresh()
    }

    /// Opens a clicked article, jumps to a clicked tab, or else moves on to
    /// the next section.
    func click(column: Int, row: Int) {
        switch hits[row] {
        case .link(let url)?:
            openInBrowser(url)
        case .tabs(let targets)?:
            if let target = targets.first(where: { $0.columns.contains(column) }) { select(target.section) }
            else { cycle() }
        case nil:
            cycle()
        }
    }

    /// ANSI for rows `firstRow...lastRow`: the section bottom-aligned, then a
    /// tab bar on the last row when more than one section is on.
    func render(width: Int, firstRow: Int, lastRow: Int, palette: Palette) -> [UInt8] {
        let columns = width - Panel.margin
        let showTabs = settings.enabled.count > 1
        // One blank row under the waveform's separator.
        let rows = lastRow - firstRow - (showTabs ? 1 : 0)
        var lines: [PanelLine]
        var links: [URL?] = []
        switch selected {
        case .info?:
            lines = InfoPanel.layout(header: info.header, fields: fields, width: columns, rows: rows)
        case .weather?:
            lines = WeatherPanel.layout(weather.state, width: columns, rows: rows)
        case .news?:
            (lines, links) = newsLines(width: columns, rows: rows)
        case nil:
            lines = []
        }
        let top = lastRow - lines.count - (showTabs && rows >= 0 && selected != nil ? 1 : 0) + 1
        hits = [:]
        for (offset, link) in links.enumerated() {
            if let link { hits[top + offset] = .link(link) }
        }
        if showTabs, rows >= 0, let selected {
            lines.append(Panel.tabBar(settings.enabled, active: selected, width: columns))
            hits[lastRow] = .tabs(Panel.tabTargets(settings.enabled, width: columns))
        }
        return Panel.render(lines, firstRow: firstRow, lastRow: lastRow, palette: palette)
    }

    /// Lines, and the article link behind each one.
    private func newsLines(width: Int, rows: Int) -> ([PanelLine], [URL?]) {
        switch news.state {
        case .waiting(let message):
            return (Panel.wrap(message, width: width, maxLines: rows).map { [Span($0, .dim)] }, [])
        case .failed(let message):
            return (Panel.wrap(message, width: width, maxLines: rows).map { [Span($0)] }, [])
        case .ready(let headlines, _):
            if newsStart >= headlines.count { newsStart = 0 }
            let page = NewsPanel.layout(headlines, start: newsStart, width: width, rows: rows)
            newsShown = page.shown
            return (page.lines, page.owners.map { $0.flatMap { headlines[$0].webURL } })
        }
    }
}
