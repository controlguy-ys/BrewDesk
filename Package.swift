// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BrewDesk", platforms: [.macOS(.v14)], products: [.executable(name: "BrewDesk", targets: ["BrewDesk"])], dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")], targets: [.executableTarget(name: "BrewDesk", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")], resources: [.copy("Resources")]), .testTarget(name: "BrewDeskTests", dependencies: ["BrewDesk"])], swiftLanguageModes: [.v5])
