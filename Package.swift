// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "rs.qubit.glance",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Glance", targets: ["Glance"])],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "Glance", dependencies: ["GlanceCore"]),
        .executableTarget(name: "GlanceChecks", dependencies: ["GlanceCore"], path: "Tests/GlanceCoreTests")
    ]
)
