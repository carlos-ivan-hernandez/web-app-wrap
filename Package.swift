// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WebWrap",
    platforms: [.macOS(.v13)],
    targets: [
        // Foundation-only logic shared by the generator and the wrapper runtime.
        .target(name: "WebWrapKit"),
        // The generator: the app you run to create wrapped apps.
        .executableTarget(name: "WebWrap", dependencies: ["WebWrapKit"]),
        // The browser shell copied into every generated app.
        .executableTarget(name: "WebWrapRuntime", dependencies: ["WebWrapKit"]),
        .testTarget(name: "WebWrapKitTests", dependencies: ["WebWrapKit"]),
    ]
)
