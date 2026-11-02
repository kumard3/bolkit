// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "SherpaKit",
  platforms: [.iOS(.v18)],
  products: [.library(name: "SherpaKit", targets: ["SherpaKit"])],
  targets: [
    .binaryTarget(name: "SherpaOnnxC", path: "Vendor/SherpaOnnxC.xcframework"),
    .target(name: "CBz", linkerSettings: [.linkedLibrary("bz2")]),
    .target(name: "SherpaKit", dependencies: ["SherpaOnnxC", "CBz"], swiftSettings: [.swiftLanguageMode(.v5)]),
  ]
)
