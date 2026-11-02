// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "BolkitCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "BolkitCore", targets: ["BolkitCore"]),
    .library(name: "SherpaKit", targets: ["SherpaKit"]),
  ],
  targets: [
    .binaryTarget(name: "whisper", path: "Vendor/whisper.xcframework"),
    .binaryTarget(name: "SherpaOnnxC", path: "Vendor/SherpaOnnxC.xcframework"),
    .target(name: "CBz", linkerSettings: [.linkedLibrary("bz2")]),
    .target(name: "SherpaKit", dependencies: ["SherpaOnnxC", "CBz"], swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "BolkitCore", dependencies: ["whisper"]),
    .testTarget(name: "BolkitCoreTests", dependencies: ["BolkitCore"]),
  ]
)
