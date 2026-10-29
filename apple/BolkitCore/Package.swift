// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "BolkitCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "BolkitCore", targets: ["BolkitCore"])],
  targets: [
    .target(name: "BolkitCore"),
    .testTarget(name: "BolkitCoreTests", dependencies: ["BolkitCore"]),
  ]
)
