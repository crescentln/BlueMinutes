// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MeetingBuddy",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MeetingBuddyDomain",
            targets: ["MeetingBuddyDomain"]
        )
    ],
    targets: [
        .target(
            name: "MeetingBuddyDomain"
        ),
        .testTarget(
            name: "MeetingBuddyDomainTests",
            dependencies: ["MeetingBuddyDomain"]
        )
    ],
    swiftLanguageModes: [.v6]
)
