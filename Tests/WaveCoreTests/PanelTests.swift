import Foundation
import Testing
@testable import WaveCore

private func text(_ lines: [PanelLine]) -> [String] { lines.map { $0.map(\.text).joined() } }

// MARK: Panel

@Test func wrapBreaksAtWordsAndMarksCuts() {
    #expect(Panel.wrap("one two three four", width: 9, maxLines: 3) == ["one two", "three", "four"])
    #expect(Panel.wrap("one two three four", width: 9, maxLines: 2) == ["one two", "three…"])
    #expect(Panel.wrap("abcdefghijkl", width: 5, maxLines: 2) == ["abcd…"])
    #expect(Panel.wrap("aaaa bbbbb cc", width: 5, maxLines: 2) == ["aaaa", "bbbb…"])
    #expect(Panel.wrap("x", width: 0, maxLines: 2).isEmpty)
}

@Test func clippedEndsInEllipsisAcrossSpans() {
    let line: PanelLine = [Span("OS: ", .bold), Span("macOS Tahoe")]
    #expect(text([Panel.clipped(line, to: 8)]) == ["OS: mac…"])
    #expect(text([Panel.clipped(line, to: 3)]) == ["OS…"])
    #expect(Panel.clipped(line, to: 40) == line)
}

@Test func tabBarHighlightsActiveAndFitsWidth() {
    let bar = Panel.tabBar(PaneSection.allCases, active: .weather, width: 30)
    #expect(Panel.width(bar) == (Panel.tabHint.isEmpty ? 19 : 30))
    #expect(bar.contains(Span("weather", .accentBold(0))))
    #expect(bar.contains(Span("info", .dim)))
    #expect(text([bar])[0].hasSuffix(Panel.tabHint.isEmpty ? "news" : "⌥⇥"))
    #expect(Panel.width(Panel.tabBar(PaneSection.allCases, active: .info, width: 10)) == 10)
}

@Test func renderBottomAlignsAndClearsAbove() {
    let out = String(decoding: Panel.render([[Span("a@b", .bold)]], firstRow: 5, lastRow: 7,
                                            palette: Palette.presets["mono"]!), as: UTF8.self)
    #expect(out.hasPrefix("\u{1B}[5;1H\u{1B}[0m\u{1B}[K\u{1B}[6;1H\u{1B}[0m\u{1B}[K"))
    #expect(out.hasSuffix("\u{1B}[7;1H\u{1B}[0m\u{1B}[K \u{1B}[1ma@b\u{1B}[0m"))
}

@Test func paletteMixRunsCentreToEdge() {
    let palette = Palette(centre: RGB(r: 0, g: 0, b: 0), edge: RGB(r: 200, g: 100, b: 50))
    #expect(palette.mix(0) == palette.centre)
    #expect(palette.mix(1) == palette.edge)
    #expect(palette.mix(0.5) == RGB(r: 100, g: 50, b: 25))
}

// MARK: Info

private let fields = [
    InfoPanel.Field("OS", "macOS Tahoe 26.1"),
    InfoPanel.Field("Host", "MacBook Pro"),
    InfoPanel.Field("Shell", "zsh"),
]

@Test func infoShowsEverythingWhenRoomy() {
    let lines = InfoPanel.layout(header: "carson@mac", fields: fields, width: 47, rows: 10)
    #expect(text(lines) == ["carson@mac", "──────────", "OS: macOS Tahoe 26.1", "Host: MacBook Pro",
                            "Shell: zsh", String(repeating: "█", count: 24)])
}

@Test func infoDropsDecorationBeforeFields() {
    #expect(text(InfoPanel.layout(header: "carson@mac", fields: fields, width: 47, rows: 4))
        == ["carson@mac", "OS: macOS Tahoe 26.1", "Host: MacBook Pro", "Shell: zsh"])
    #expect(text(InfoPanel.layout(header: "carson@mac", fields: fields, width: 47, rows: 2))
        == ["OS: macOS Tahoe 26.1", "Host: MacBook Pro"])
}

@Test func infoIsEmptyWithoutRoomAndTruncatesValues() {
    #expect(InfoPanel.layout(header: "a@b", fields: fields, width: 47, rows: 0).isEmpty)
    #expect(InfoPanel.layout(header: "a@b", fields: fields, width: 5, rows: 10).isEmpty)
    let cpu = InfoPanel.layout(header: "a@b", fields: [.init("CPU", "Apple M3 Max (16)")], width: 13, rows: 1)
    #expect(text(cpu) == ["CPU: Apple M…"])
}

@Test func uptimeAndUsageFormatting() {
    #expect(InfoPanel.uptime(seconds: 59) == "0m")
    #expect(InfoPanel.uptime(seconds: 3 * 3600 + 120) == "3h 2m")
    #expect(InfoPanel.uptime(seconds: 2 * 86_400 + 5 * 60) == "2d 0h 5m")
    let gib: UInt64 = 1 << 30
    #expect(InfoPanel.usage(used: 9 * gib / 2, total: 18 * gib) == "4.5 / 18.0 GiB (25%)")
    #expect(InfoPanel.usage(used: 1, total: 0) == "?")
}

// MARK: Settings and options

@Test func paneSettingsDefaultToAllOnWithBuiltInSources() {
    let store = UserDefaults(suiteName: "soundcrest-tests-\(UUID())")!
    let settings = PaneSettings.stored(in: store)
    #expect(settings.enabled == [.info, .weather, .news])
    #expect(settings.selected == .info)
    #expect(settings.weatherLocation == nil)
    #expect(settings.newsSources.map(\.id) == ["bbc", "nyt", "npr", "google"])
}

@Test func paneSettingsRememberChoices() {
    let store = UserDefaults(suiteName: "soundcrest-tests-\(UUID())")!
    PaneSettings.setEnabled(.info, false, in: store)
    PaneSettings.select(.news, in: store)
    PaneSettings.setWeatherLocation("Toronto", in: store)
    PaneSettings.setNewsSources(NewsSource.list("ft,bbc")!, in: store)
    let settings = PaneSettings.stored(in: store)
    #expect(settings.enabled == [.weather, .news])
    #expect(settings.selected == .news)
    #expect(settings.weatherLocation == "Toronto")
    #expect(settings.newsSources.map(\.id) == ["ft", "bbc"])
    PaneSettings.setWeatherLocation(nil, in: store)
    #expect(PaneSettings.stored(in: store).weatherLocation == nil)
}

@Test func paneSettingsSkipDisabledSelectionAndCycle() {
    let store = UserDefaults(suiteName: "soundcrest-tests-\(UUID())")!
    PaneSettings.select(.weather, in: store)
    PaneSettings.setEnabled(.weather, false, in: store)
    var settings = PaneSettings.stored(in: store)
    #expect(settings.selected == .info)
    #expect(settings.nextSection == .news)
    settings.selected = .news
    #expect(settings.nextSection == .info)

    PaneSettings.setEnabled(.info, false, in: store)
    PaneSettings.setEnabled(.news, false, in: store)
    settings = PaneSettings.stored(in: store)
    #expect(settings.selected == nil)
    #expect(settings.nextSection == nil)
}

@Test func optionsParsePaneSections() {
    #expect(Options.parse(["--pane-info", "off"])?.mode == .paneSection(.info, false))
    #expect(Options.parse(["--pane-weather", "on"])?.mode == .paneSection(.weather, true))
    #expect(Options.parse(["--pane-news", "off"])?.mode == .paneSection(.news, false))
    #expect(Options.parse(["--pane-news"]) == nil)
    #expect(Options.parse(["--pane-news", "maybe"]) == nil)
}

@Test func optionsParseWeatherLocationAndSources() {
    #expect(Options.parse(["--weather-location", "New York"])?.mode == .weatherLocation("New York"))
    #expect(Options.parse(["--weather-location", "Auto"])?.mode == .weatherLocation(nil))
    #expect(Options.parse(["--weather-location", " "]) == nil)
    #expect(Options.parse(["--news-sources", "bbc, NYT"])?.mode == .newsSources(NewsSource.list("bbc,nyt")!))
    #expect(Options.parse(["--news-sources", "bbc,fox"]) == nil)
    #expect(Options.parse(["--news-sources", ","]) == nil)
}

@Test func tmuxSendsOptionTabToTheWaveformPane() {
    let words = PaneLayout.tmuxArguments(tmux: "/bin/tmux", shell: "/bin/zsh", executable: "/bin/soundcrest",
                                         paneCols: 40)
    let joined = words.joined(separator: " ")
    #expect(joined.contains("bind-key -n M-Tab send-keys -t :.1 Tab"))
}

// MARK: Weather

private let forecastJSON = """
{"current_units":{"temperature_2m":"°F","wind_speed_10m":"mp/h"},
 "current":{"temperature_2m":51.6,"apparent_temperature":49.2,"relative_humidity_2m":78,
            "weather_code":61,"wind_speed_10m":9.6,"is_day":1},
 "daily":{"time":["2026-11-07","2026-11-08","2026-11-09","2026-11-10"],"weather_code":[61,2,0,95],
          "temperature_2m_max":[54,56.4,60,58],"temperature_2m_min":[44,45,47.5,50],
          "precipitation_probability_max":[80,10,null,60]}}
"""

private func forecast() throws -> Forecast {
    try JSONDecoder().decode(Forecast.self, from: Data(forecastJSON.utf8))
}

@Test func forecastDecodesOpenMeteo() throws {
    let forecast = try forecast()
    #expect(forecast.current.code == 61)
    #expect(forecast.daily.rainChance == [80, 10, nil, 60])
}

@Test func forecastURLRoundsPositionAndPicksUnits() {
    let metric = Forecast.url(latitude: 43.65432, longitude: -79.38321, imperial: false).absoluteString
    #expect(metric.contains("latitude=43.65") && metric.contains("longitude=-79.38"))
    #expect(!metric.contains("fahrenheit"))
    let imperial = Forecast.url(latitude: 0, longitude: 0, imperial: true).absoluteString
    #expect(imperial.contains("temperature_unit=fahrenheit") && imperial.contains("wind_speed_unit=mph"))
}

@Test func conditionsCoverWMOCodes() {
    #expect(Condition(code: 0) == .clear)
    #expect(Condition(code: 3) == .cloudy)
    #expect(Condition(code: 48) == .fog)
    #expect(Condition(code: 65) == .rain)
    #expect(Condition(code: 86) == .snow)
    #expect(Condition(code: 99) == .thunder)
    for condition in [Condition.clear, .partlyCloudy, .cloudy, .fog, .drizzle, .rain, .snow, .showers, .thunder] {
        for isDay in [true, false] {
            #expect(condition.icon(isDay: isDay).map(\.count) == [11, 11, 11])
        }
    }
}

@Test func weatherLayoutShowsCurrentAndDays() throws {
    let fetched = Date(timeIntervalSince1970: 1_000_000)
    let state = WeatherState.ready(place: "Toronto", forecast: try forecast(), fetched: fetched)
    let lines = text(WeatherPanel.layout(state, width: 47, rows: 12, now: fetched.addingTimeInterval(300)))
    #expect(lines.count == 9)
    #expect(lines[0] == "Toronto  5m ago")
    #expect(lines[1].hasSuffix("Rain"))
    #expect(lines[2].hasSuffix("52°F  feels 49°"))
    #expect(lines[3].hasSuffix("78% humid · 10 mph"))
    #expect(lines[4] == "")
    #expect(lines[5] == "Today 44°  54°  Rain 80%")
    #expect(lines[6].hasSuffix(" 45°  56°  Partly cloudy"))
    #expect(lines[7].hasSuffix(" 48°  60°  Clear"))
    #expect(lines[8].hasSuffix(" 50°  58°  Thunderstorm 60%"))
}

@Test func weatherLayoutShrinksAndWrapsMessages() throws {
    let state = WeatherState.ready(place: "Toronto", forecast: try forecast(), fetched: Date())
    #expect(WeatherPanel.layout(state, width: 47, rows: 4).count == 4)
    #expect(text(WeatherPanel.layout(state, width: 47, rows: 1)) == ["52°F  feels 49°"])
    let narrow = text(WeatherPanel.layout(state, width: 20, rows: 2))
    #expect(narrow == ["Rain", "52°F  feels 49°"])
    let message = WeatherPanel.layout(.failed("Location access is off. Allow it in System Settings"),
                                      width: 20, rows: 5)
    #expect(text(message) == ["Location access is", "off. Allow it in", "System Settings"])
}

@Test func placeSearchTakesFirstResult() {
    let data = Data(#"{"results":[{"name":"Toronto","latitude":43.7,"longitude":-79.4,"country":"Canada"}]}"#.utf8)
    #expect(Place.firstResult(in: data) == Place(name: "Toronto", latitude: 43.7, longitude: -79.4))
    #expect(Place.firstResult(in: Data(#"{"generationtime_ms":0.1}"#.utf8)) == nil)
    #expect(Place.searchURL("New York").absoluteString.contains("name=New%20York"))
}

// MARK: News

private let rss = """
<?xml version="1.0"?><rss version="2.0"><channel><title>Feed title</title>
<item><title><![CDATA[First  story]]></title><link>https://a.example/1</link>
  <pubDate>Sat, 07 Nov 2026 16:58:12 GMT</pubDate></item>
<item><title>Second &amp; story</title><link>https://a.example/2</link>
  <pubDate>Sat, 07 Nov 2026 18:00:00 +0000</pubDate></item>
<item><title> </title></item>
</channel></rss>
"""

@Test func rssReaderTakesItemTitlesLinksAndDates() {
    let items = RSSReader.headlines(from: Data(rss.utf8), tag: "BBC")
    #expect(items.map(\.title) == ["First story", "Second & story"])
    #expect(items.map(\.link) == ["https://a.example/1", "https://a.example/2"])
    let iso = ISO8601DateFormatter()
    #expect(items[0].date == iso.date(from: "2026-11-07T16:58:12Z"))
    #expect(items[1].date == iso.date(from: "2026-11-07T18:00:00Z"))
    #expect(items.allSatisfy { $0.tag == "BBC" })
}

@Test func mergeTakesTurnsNewestFirstWithoutDuplicates() {
    func item(_ title: String, _ tag: String, _ time: Double) -> Headline {
        Headline(title: title, tag: tag, date: Date(timeIntervalSince1970: time), link: nil)
    }
    let merged = NewsPanel.merge([
        [item("a1", "A", 1), item("a2", "A", 2), item("a3", "A", 3)],
        [item("b1", "B", 5), item("A2", "B", 9)],
    ])
    // "a2" repeats "A2" ignoring case, so only the first one seen stays.
    #expect(merged.map(\.title) == ["a3", "A2", "b1", "a1"])
}

@Test func newsLayoutSpacesArticlesWithSummariesAndOwners() {
    let headlines = [
        Headline(title: "Short one", tag: "BBC", date: nil, link: "https://bbc.example/1",
                 summary: "The first few words of the story body go here and then some more."),
        Headline(title: "A much longer headline that needs two lines", tag: "WaPo", date: nil, link: nil),
        Headline(title: "Third", tag: "NYT", date: nil, link: nil),
    ]
    let page = NewsPanel.layout(headlines, start: 0, width: 30, rows: 7)
    #expect(page.shown == 2)
    #expect(text(page.lines) == [
        "BBC  Short one",
        "     The first few words of",
        "     the story body go here…",
        "",
        "WaPo A much longer headline",
        "     that needs two lines",
    ])
    #expect(page.owners == [0, 0, 0, nil, 1, 1])
}

@Test func newsLayoutDropsSummaryLinesBeforeArticles() {
    let headlines = [
        Headline(title: "One", tag: "BBC", date: nil, link: nil, summary: "alpha beta gamma delta epsilon zeta"),
        Headline(title: "Two", tag: "NYT", date: nil, link: nil, summary: "eta theta"),
    ]
    let page = NewsPanel.layout(headlines, start: 1, width: 20, rows: 4, summaryLines: 2)
    #expect(text(page.lines) == ["NYT  Two", "     eta theta", "", "BBC  One"])
    #expect(page.owners == [1, 1, nil, 0])
}

@Test func headlineOnlyOpensWebLinks() {
    #expect(Headline(title: "a", tag: "t", date: nil, link: "https://x.example/a").webURL != nil)
    #expect(Headline(title: "a", tag: "t", date: nil, link: "file:///etc/passwd").webURL == nil)
    #expect(Headline(title: "a", tag: "t", date: nil, link: nil).webURL == nil)
}

@Test func rssSummariesAreCleanedAndSkipRepeats() {
    let feed = """
    <rss><channel>
    <item><title>Big news</title><description><![CDATA[<p>It&#8217;s <b>bigger</b> than&nbsp;expected &amp; more.</p>]]></description></item>
    <item><title>Echo story</title><description>&lt;a href="x"&gt;Echo story&lt;/a&gt;&amp;nbsp;CBS</description></item>
    <item><title>Bare</title></item>
    </channel></rss>
    """
    let items = RSSReader.headlines(from: Data(feed.utf8), tag: "GN")
    #expect(items.map(\.summary) == ["It’s bigger than expected & more.", nil, nil])
}

@Test func htmlTextDecodesEntitiesAndStripsTags() {
    #expect(HTMLText.plain("<i>A</i> &amp; B &#x2014; C&hellip; &bogus; 5 & 6") == "A & B — C… &bogus; 5 & 6")
}

@Test func paneInputReadsTabsAndLeftClicks() {
    var input = PaneInput()
    #expect(input.feed(Array("\t\u{1B}[<0;12;30M\u{1B}[<0;12;30m".utf8)) == [.tab, .click(column: 12, row: 30)])
    // Right button and drag are ignored; the wheel scrolls.
    #expect(input.feed(Array("\u{1B}[<2;1;1M\u{1B}[<32;5;5M".utf8)).isEmpty)
    #expect(input.feed(Array("\u{1B}[<64;3;4M\u{1B}[<65;3;5M".utf8)) == [.scroll(-1, row: 4), .scroll(1, row: 5)])
}

@Test func paneInputWaitsForSplitSequences() {
    var input = PaneInput()
    #expect(input.feed(Array("\u{1B}[<0;4".utf8)).isEmpty)
    #expect(input.feed(Array(";9M\t".utf8)) == [.click(column: 4, row: 9), .tab])
    #expect(input.feed(Array("\u{1B}x\t".utf8)) == [.tab])
}

@Test func tabTargetsMatchTabBarColumns() {
    let targets = Panel.tabTargets(PaneSection.allCases, width: 47)
    #expect(targets.map(\.section) == [.info, .weather, .news])
    #expect(targets.map(\.columns) == [2...5, 8...14, 17...20])
    // " info  weather  news": column 2 is the first letter after the margin.
    let bar = " " + text([Panel.tabBar(PaneSection.allCases, active: .info, width: 47)])[0]
    for target in targets {
        let letters = bar.dropFirst(target.columns.lowerBound - 1).prefix(target.columns.count)
        #expect(String(letters) == target.section.title)
    }
}

@Test func tmuxForwardsClicksButKeepsShellFocused() {
    let joined = PaneLayout.tmuxArguments(tmux: "/bin/tmux", shell: "/bin/zsh", executable: "/bin/soundcrest",
                                          paneCols: 40).joined(separator: " ")
    #expect(joined.contains("bind-key -n MouseDown1Pane select-pane -t :.0 \\; send-keys -M"))
}

@Test func newsSourcePresetsAreKnown() {
    #expect(NewsSource.preset(named: "BBC")?.tag == "BBC")
    #expect(NewsSource.list("guardian,aljazeera")?.map(\.tag) == ["GDN", "AJ"])
    #expect(Set(NewsSource.presets.map(\.id)).count == NewsSource.presets.count)
}

// MARK: Location helper

@Test func locationAppCopiesExecutableAndReportsChanges() throws {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("soundcrest-tests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: support) }
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let binary = support.appendingPathComponent("bin")
    try Data("v1".utf8).write(to: binary)

    let first = try LocationApp.install(executable: binary.path, in: support)
    #expect(first.changed)
    #expect(first.bundle.lastPathComponent == "soundcrest.app")
    let copy = LocationApp.executable(of: first.bundle)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: copy.path)) == nil)
    #expect(try Data(contentsOf: copy) == Data("v1".utf8))
    let plist = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: LocationApp.infoPlist(of: first.bundle)), format: nil) as? [String: Any]
    #expect(plist?["CFBundleIdentifier"] as? String == "local.soundcrest")
    #expect(plist?["LSUIElement"] as? Bool == true)
    #expect(plist?["NSLocationWhenInUseUsageDescription"] is String)

    #expect(try !LocationApp.install(executable: binary.path, in: support).changed)
    try Data("v2".utf8).write(to: binary)
    #expect(try LocationApp.install(executable: binary.path, in: support).changed)
    #expect(try Data(contentsOf: copy) == Data("v2".utf8))
}

@Test func locationOutcomeRoundTrips() throws {
    let outcome = LocationApp.Outcome(place: Place(name: "Montréal", latitude: 45.5, longitude: -73.6),
                                      failure: nil, finished: Date(timeIntervalSince1970: 100))
    let decoded = try JSONDecoder().decode(LocationApp.Outcome.self, from: JSONEncoder().encode(outcome))
    #expect(decoded == outcome)
    #expect(Options.parse([LocationApp.runFlag])?.mode == .locate)
}

// MARK: Logos

@Test func logosAreRectangularAndPickedFromOSRelease() {
    let all = [SystemLogo.macOS] + ["ubuntu", "debian", "fedora", "arch", "gentoo"].map {
        SystemLogo.linux(osRelease: "ID=\($0)\n")
    }
    for logo in all {
        #expect(Set(logo.map(\.count)).count == 1)
        #expect(logo.count >= 5 && logo[0].count <= 15)
    }
    #expect(SystemLogo.linux(osRelease: "ID=linuxmint\nID_LIKE=\"ubuntu debian\"\n")
        == SystemLogo.linux(osRelease: "ID=ubuntu\n"))
    #expect(SystemLogo.linux(osRelease: "ID=manjaro\nID_LIKE=arch\n") == SystemLogo.linux(osRelease: "ID=arch\n"))
    #expect(SystemLogo.linux(osRelease: "ID=gentoo\n") == SystemLogo.linux(osRelease: ""))  // Tux
    #expect(SystemLogo.linux(osRelease: "ID=ubuntu") != SystemLogo.linux(osRelease: ""))
}

@Test func infoPutsLogoBesideDetailsWhenItFits() {
    let logo = ["/\\", "\\/", "##"]
    let lines = InfoPanel.layout(header: "me@mac", fields: fields, width: 40, rows: 10, logo: logo)
    #expect(text(lines).prefix(4) == ["/\\  me@mac", "\\/  ──────", "##  OS: macOS Tahoe 26.1", "    Host: MacBook Pro"])
    #expect(lines[0][0].style == .accent(0))
    #expect(lines[2][0].style == .accent(1))
    #expect(lines.count == 6)
}

@Test func infoDropsLogoWhenNarrowOrShort() {
    let logo = [String](repeating: "############", count: 4)
    let narrow = InfoPanel.layout(header: "me@mac", fields: fields, width: 30, rows: 10, logo: logo)
    #expect(narrow == InfoPanel.layout(header: "me@mac", fields: fields, width: 30, rows: 10))
    let short = InfoPanel.layout(header: "me@mac", fields: fields, width: 47, rows: 3, logo: logo)
    #expect(short == InfoPanel.layout(header: "me@mac", fields: fields, width: 47, rows: 3))
}
