// swift-tools-version:5.9
import PackageDescription

let infoPlist = Context.packageDirectory + "/Support/Info.plist"

let package = Package(
    name: "soundcrest",
    platforms: [.macOS("14.2")],  // Core Audio process taps; Linux records with parec
    targets: [
        .target(name: "WaveCore"),
        .executableTarget(
            name: "soundcrest",
            dependencies: ["WaveCore"],
            // Embeds the usage descriptions macOS shows in permission prompts.
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", infoPlist,
            ], .when(platforms: [.macOS]))]
        ),
        .testTarget(name: "WaveCoreTests", dependencies: ["WaveCore"]),
    ]
)
