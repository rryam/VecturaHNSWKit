// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "VecturaHNSWKit",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
    .tvOS(.v18),
    .visionOS(.v2),
    .watchOS(.v11),
  ],
  products: [
    .library(
      name: "VecturaHNSWKit",
      targets: ["VecturaHNSWKit"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/rryam/VecturaKit.git", from: "6.1.0"),
  ],
  targets: [
    .target(
      name: "VecturaHNSWKit",
      dependencies: [
        .product(name: "VecturaKit", package: "VecturaKit"),
      ],
      linkerSettings: [
        .linkedLibrary("sqlite3"),
      ]
    ),
    .testTarget(
      name: "VecturaHNSWKitTests",
      dependencies: [
        "VecturaHNSWKit",
        .product(name: "VecturaKit", package: "VecturaKit"),
      ]
    ),
  ]
)
