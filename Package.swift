// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SteamKit",
    // Mac only: it reads the Steam client's folders on this Mac.
    platforms: [.macOS(.v14)],
    products: [
        // Steam on this Mac: its libraries, installed games, accounts, steam:// links, the store's
        // details and pictures, and Valve's KeyValues text. No SwiftUI, no network.
        .library(name: "SteamKit", targets: ["SteamKit"]),
    ],
    targets: [
        .target(name: "SteamKit"),
        .testTarget(name: "SteamKitTests", dependencies: ["SteamKit"]),
    ]
)
