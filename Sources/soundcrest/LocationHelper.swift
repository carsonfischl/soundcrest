import AppKit
import CoreLocation
import Foundation
import WaveCore

/// Starts and runs the location helper app (see `LocationApp`).
enum LocationHelper {
    static let file = "location.json"
    private static let timeout: TimeInterval = 120

    /// Opens the helper in the background. It writes `file` and quits.
    static func launch() {
        guard let path = Bundle.main.executablePath,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let installed = try? LocationApp.install(executable: path, in: support),
              !installed.changed || run("/usr/bin/codesign", ["--force", "--sign", "-", installed.bundle.path]) else {
            FeedCache.write(LocationApp.Outcome(place: nil, failure: "Couldn't set up the location helper."), file)
            return
        }
        _ = run("/usr/bin/open", ["-g", "-j", "-n", installed.bundle.path, "--args", LocationApp.runFlag],
                wait: false)
    }

    /// True when the tool started, and exited cleanly if `wait`.
    private static func run(_ tool: String, _ arguments: [String], wait: Bool = true) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        guard wait else { return true }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Runs inside the helper app: asks for the position once, records the
    /// outcome and quits.
    @MainActor static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // macOS shows the permission prompt only for the active app. Once
        // answered, later lookups stay in the background.
        if CLLocationManager().authorizationStatus == .notDetermined { app.activate(ignoringOtherApps: true) }
        let locator = Locator(timeout: timeout)
        locator.locate { result in
            switch result {
            case .failure(let failure):
                finish(LocationApp.Outcome(place: nil, failure: failure.message))
            case .success(let location):
                Locator.name(of: location) { name in
                    finish(LocationApp.Outcome(place: Place(name: name, latitude: location.coordinate.latitude,
                                                            longitude: location.coordinate.longitude),
                                               failure: nil))
                }
            }
        }
        app.run()
        exit(0)
    }

    private static func finish(_ outcome: LocationApp.Outcome) -> Never {
        FeedCache.write(outcome, file)
        exit(0)
    }
}
