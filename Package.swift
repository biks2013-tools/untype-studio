// swift-tools-version:6.2
// untype studio — the recordings explorer (was ntakker-studio, split out of
// the ntakker repository on 2026-11-20).
//
// Targets:
//   untype-studio      the Dock app (SwiftUI)
//   UntypeStudioKit    its testable logic
//   NtakkerCore        vendored copy of ntakker's engine: settings file,
//   NtakkerSettingsUI  transcript formats, transcription and Ask providers,
//                      echo canceller, and the shared Settings panes. Kept
//                      under ntakker's module names so a newer copy can be
//                      dropped in from the ntakker repository.
import PackageDescription

// Without full Xcode, Swift Testing's framework lives in the
// CommandLineTools frameworks folder; SwiftPM adds only -I for it.
let testingFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

let package = Package(
    name: "untype-studio",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "untype-studio", targets: ["untype-studio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.4"),
        // WhisperKit (on-device Whisper) for re-transcription. Same pin as ntakker.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "0.18.0"),
        // Parakeet TDT V3 (on-device) for re-transcription. Same pin as
        // ntakker: 0.9.x fails Swift 6 strict-concurrency checks.
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.8.2"),
    ],
    targets: [
        .target(
            name: "NtakkerCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/NtakkerCore"
        ),
        .target(
            name: "NtakkerSettingsUI",
            dependencies: [
                "NtakkerCore",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/NtakkerSettingsUI"
        ),
        .target(
            name: "UntypeStudioKit",
            dependencies: [
                "NtakkerCore",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/UntypeStudioKit"
        ),
        // The Dock app. Bundle id com.giorgosmarinos.untype-studio; the
        // Info.plist is embedded so the bare binary carries it too.
        .executableTarget(
            name: "untype-studio",
            dependencies: [
                "NtakkerCore",
                "UntypeStudioKit",
                "NtakkerSettingsUI",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/untype-studio",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/UntypeStudio-Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "UntypeStudioTests",
            dependencies: ["UntypeStudioKit", "NtakkerCore"],
            path: "Tests/UntypeStudioTests",
            swiftSettings: [.unsafeFlags(["-F", testingFrameworks])],
            linkerSettings: [
                .unsafeFlags([
                    "-F", testingFrameworks,
                    "-Xlinker", "-rpath", "-Xlinker", testingFrameworks,
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ]
        ),
    ],
    // Swift 5 language mode, as in ntakker: the vendored engine is not
    // migrated to Swift 6 strict concurrency.
    swiftLanguageModes: [.v5]
)
