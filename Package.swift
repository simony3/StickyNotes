// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickyNotes",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "StickyNotesGeometry",
            path: "Sources/StickyNotesGeometry"
        ),
        .executableTarget(
            name: "StickyNotes",
            dependencies: ["StickyNotesGeometry"],
            path: "Sources/StickyNotes"
        ),
        .executableTarget(
            name: "StickyNotesGeometryChecks",
            dependencies: ["StickyNotesGeometry"],
            path: "Tests/StickyNotesGeometryChecks"
        )
    ]
)
