// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WebAppWrap",
    platforms: [.macOS(.v13)],
    targets: [
        // Foundation-only logic shared by the generator and the wrapper runtime.
        .target(name: "WebAppWrapKit"),
        // The generator: the app you run to create wrapped apps.
        .executableTarget(name: "WebAppWrap", dependencies: ["WebAppWrapKit"]),
        // The browser shell copied into every generated app.
        .executableTarget(name: "WebAppWrapRuntime", dependencies: ["WebAppWrapKit"]),
        .testTarget(name: "WebAppWrapKitTests", dependencies: ["WebAppWrapKit"]),
    ]
)
