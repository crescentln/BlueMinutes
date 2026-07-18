// swift-tools-version: 6.1

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
        ),
        .library(
            name: "MeetingBuddyApplication",
            targets: ["MeetingBuddyApplication"]
        ),
        .library(
            name: "MeetingBuddyPersistence",
            targets: ["MeetingBuddyPersistence"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.11.1"
        )
    ],
    targets: [
        .target(
            name: "MeetingBuddyDomain"
        ),
        .target(
            name: "MeetingBuddyApplication",
            dependencies: ["MeetingBuddyDomain"]
        ),
        .target(
            name: "MeetingBuddyPersistence",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MeetingBuddyDomainTests",
            dependencies: ["MeetingBuddyDomain"]
        ),
        .testTarget(
            name: "MeetingBuddyPersistenceTests",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain",
                "MeetingBuddyPersistence",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
