import Foundation

/// Starts the desktop background at login through a launchd agent. launchd reads
/// the folder at login, so adding or removing the file leaves a running
/// background alone. There is no KeepAlive: turning it off must keep it off.
public enum LoginItem {
    private static let label = "local.soundcrest"

    public static var agentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    public static func file(in directory: URL) -> URL {
        directory.appendingPathComponent(label + ".plist")
    }

    /// Homebrew's versioned Cellar path disappears on upgrade; its bin link does not.
    public static func stablePath(_ path: String) -> String {
        guard let cellar = path.range(of: "/Cellar/") else { return path }
        return path[..<cellar.lowerBound] + "/bin/" + (path as NSString).lastPathComponent
    }

    public static func install(executable: String, in directory: URL = agentsDirectory) throws {
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--wallpaper-run"],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(in: directory), options: .atomic)
    }

    public static func remove(in directory: URL = agentsDirectory) throws {
        let url = file(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
