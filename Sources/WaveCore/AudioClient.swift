/// A process known to Core Audio. Capturing marks a process as running output,
/// so soundcrest listeners must not count, or they would hold each other open.
public struct AudioClient {
    private static let ownBundleID = "local.soundcrest"

    public let bundleID: String?
    public let isRunningOutput: Bool

    public init(bundleID: String?, isRunningOutput: Bool) {
        self.bundleID = bundleID
        self.isRunningOutput = isRunningOutput
    }

    public static func anyPlaying(_ clients: [AudioClient]) -> Bool {
        clients.contains { $0.isRunningOutput && $0.bundleID != ownBundleID }
    }
}
