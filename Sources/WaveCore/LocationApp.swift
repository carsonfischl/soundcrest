import Foundation

/// macOS asks about Location Services only for apps, never for command-line
/// tools, so the pane finds its position through a tiny app bundle holding a
/// copy of soundcrest. Location Services ignores a bundle whose executable is a
/// link to a file outside it, so it has to be a real copy.
public enum LocationApp {
    public static let bundleID = "local.soundcrest"
    public static let runFlag = "--locate"
    static let executableName = "soundcrest"
    static let usage = "soundcrest uses your location to show local weather in the Terminal pane. "
        + "A rounded position goes to Open-Meteo for the forecast, and to Apple for the place name."

    /// What the helper found, written to the shared cache for panes to read.
    public struct Outcome: Codable, Equatable, Sendable {
        public let place: Place?
        public let failure: String?
        public let finished: Date

        public init(place: Place?, failure: String?, finished: Date = Date()) {
            self.place = place
            self.failure = failure
            self.finished = finished
        }
    }

    public static func bundle(in support: URL) -> URL {
        support.appendingPathComponent("soundcrest", isDirectory: true)
            .appendingPathComponent("soundcrest.app", isDirectory: true)
    }

    public static func executable(of bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/MacOS/\(executableName)")
    }

    public static func infoPlist(of bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/Info.plist")
    }

    public static let info: [String: Any] = [
        "CFBundleIdentifier": bundleID,
        "CFBundleName": "soundcrest",
        "CFBundleDisplayName": "soundcrest",
        "CFBundleExecutable": executableName,
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "LSUIElement": true,
        "NSLocationUsageDescription": usage,
        "NSLocationWhenInUseUsageDescription": usage,
    ]

    /// Writes or repairs the bundle so it runs a copy of `executable`. Returns
    /// true when anything changed, so the caller re-signs it. An up-to-date
    /// bundle is left alone so Location Services keeps its permission.
    public static func install(executable: String, in support: URL) throws -> (bundle: URL, changed: Bool) {
        let bundle = bundle(in: support)
        let manager = FileManager.default
        let copy = Self.executable(of: bundle)
        try manager.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        var changed = false

        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        let plistURL = infoPlist(of: bundle)
        if (try? Data(contentsOf: plistURL)) != plist {
            try plist.write(to: plistURL, options: .atomic)
            changed = true
        }

        let isLink = (try? manager.destinationOfSymbolicLink(atPath: copy.path)) != nil
        if isLink || !manager.contentsEqual(atPath: copy.path, andPath: executable) {
            try? manager.removeItem(at: copy)
            try manager.copyItem(atPath: executable, toPath: copy.path)
            changed = true
        }
        return (bundle, changed)
    }
}
