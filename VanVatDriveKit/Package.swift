// swift-tools-version: 5.9
import PackageDescription

// Shared by the Van Vat Drive app and the DoubleClips "Storage" tab (OpenEditzClient).
let package = Package(
    name: "VanVatDriveKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "VanVatDriveKit", targets: ["VanVatDriveKit"])],
    targets: [.target(name: "VanVatDriveKit")]
)
