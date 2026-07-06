// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "geokit",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "geokit", targets: ["Geo"]),
        .executable(name: "geokit-review", targets: ["GeoReview"])
    ],
    targets: [
        .executableTarget(
            name: "Geo",
            path: "Sources/Geo"
        ),
        .executableTarget(
            name: "GeoReview",
            path: "Sources/GeoReview"
        ),
        .testTarget(
            name: "GeoTests",
            dependencies: ["Geo"],
            path: "Tests/GeoTests"
        )
    ]
)
