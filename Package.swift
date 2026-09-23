// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PhotoViewer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PhotoViewer", targets: ["PhotoViewer"])],
    targets: [
        .target(name: "PhotoViewerCore"),
        .executableTarget(name: "PhotoViewer", dependencies: ["PhotoViewerCore"]),
        .executableTarget(name: "PhotoViewerChecks", dependencies: ["PhotoViewerCore"], path: "Tests/PhotoViewerCoreTests")
    ]
)
