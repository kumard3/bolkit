// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "BolkitCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "BolkitCore", targets: ["BolkitCore"])],
  targets: [
    .binaryTarget(name: "whisper", path: "Vendor/whisper.xcframework"),
    .target(name: "BolkitCore", dependencies: ["whisper"]),
    .testTarget(name: "BolkitCoreTests", dependencies: ["BolkitCore"]),
  ]
)
