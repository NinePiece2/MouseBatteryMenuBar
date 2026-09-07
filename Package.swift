// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LogiMouseBatteryMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LogiMouseBatteryMenuBar",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)