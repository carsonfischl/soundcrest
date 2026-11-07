import Foundation

/// The views that take turns under the pane's waveform.
public enum PaneSection: String, CaseIterable, Sendable {
    case info, weather, news

    public var title: String { rawValue }
}

/// What the pane shows, remembered across windows. Read again while panes run,
/// so `--pane-news off` takes effect without opening a new window.
public struct PaneSettings: Equatable, Sendable {
    private static let selectedKey = "paneSection"
    private static let locationKey = "weatherLocation"
    private static let sourcesKey = "newsSources"

    private static func enabledKey(_ section: PaneSection) -> String {
        "pane" + section.rawValue.prefix(1).uppercased() + section.rawValue.dropFirst()
    }

    public var enabled: [PaneSection]
    public var selected: PaneSection?
    /// A place name to look up, or nil to use Location Services.
    public var weatherLocation: String?
    public var newsSources: [NewsSource]

    public static func stored(in store: UserDefaults) -> PaneSettings {
        let enabled = PaneSection.allCases.filter { store.object(forKey: enabledKey($0)) as? Bool ?? true }
        let selected = store.string(forKey: selectedKey).flatMap(PaneSection.init(rawValue:))
        let sources = store.stringArray(forKey: sourcesKey)?.compactMap(NewsSource.preset(named:))
        return PaneSettings(
            enabled: enabled,
            selected: selected.flatMap { enabled.contains($0) ? $0 : nil } ?? enabled.first,
            weatherLocation: store.string(forKey: locationKey),
            newsSources: sources.flatMap { $0.isEmpty ? nil : $0 } ?? NewsSource.defaults)
    }

    public static func setEnabled(_ section: PaneSection, _ on: Bool, in store: UserDefaults) {
        store.set(on, forKey: enabledKey(section))
    }

    public static func select(_ section: PaneSection, in store: UserDefaults) {
        store.set(section.rawValue, forKey: selectedKey)
    }

    public static func setWeatherLocation(_ place: String?, in store: UserDefaults) {
        if let place { store.set(place, forKey: locationKey) } else { store.removeObject(forKey: locationKey) }
    }

    public static func setNewsSources(_ sources: [NewsSource], in store: UserDefaults) {
        store.set(sources.map(\.id), forKey: sourcesKey)
    }

    /// The enabled section after the selected one, wrapping around.
    public var nextSection: PaneSection? {
        guard let selected, let index = enabled.firstIndex(of: selected) else { return enabled.first }
        return enabled[(index + 1) % enabled.count]
    }
}
