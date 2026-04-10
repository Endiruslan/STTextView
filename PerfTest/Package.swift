// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "STTextViewPerfTest",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "PerfTest",
            dependencies: [
                .product(name: "STTextView", package: "sttextview-fork"),
            ],
            path: "Sources"
        ),
    ]
)
