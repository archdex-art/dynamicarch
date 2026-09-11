// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DynamicArch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DynamicArch", targets: ["DynamicArch"])
    ],
    targets: [
        .executableTarget(
            name: "DynamicArch",
            path: "Sources/DynamicArch",
            swiftSettings: [
                // Language mode 5: the app bridges a lot of C / CoreAudio / IOKit callback
                // surface where Swift 6 sendability checking buys nothing but noise.
                // All UI and service state is explicitly @MainActor isolated instead.
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-enforce-exclusivity=unchecked"], .when(configuration: .release)),
            ]
        )
    ]
)
