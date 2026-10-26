// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Signalperch", platforms: [.macOS(.v14)], products: [.executable(name: "Signalperch", targets: ["Signalperch"])], targets: [.executableTarget(name: "Signalperch", resources: [.copy("Resources")]), .testTarget(name: "SignalperchTests", dependencies: ["Signalperch"])])
