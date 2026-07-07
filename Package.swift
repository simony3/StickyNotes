// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickyNotes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "StickyNotes",
            path: "Sources/StickyNotes"
        )
    ]
)
