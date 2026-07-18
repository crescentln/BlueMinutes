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
        ),
        .library(
            name: "MeetingBuddyTasks",
            targets: ["MeetingBuddyTasks"]
        ),
        .library(
            name: "MeetingBuddyMedia",
            targets: ["MeetingBuddyMedia"]
        ),
        .library(
            name: "MeetingBuddyFeatures",
            targets: ["MeetingBuddyFeatures"]
        ),
        .executable(
            name: "MeetingBuddyApp",
            targets: ["MeetingBuddyApp"]
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
        .target(
            name: "MeetingBuddyTasks",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain"
            ]
        ),
        .target(
            name: "MeetingBuddyMedia",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain"
            ]
        ),
        .target(
            name: "MeetingBuddyFeatures",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain"
            ]
        ),
        .executableTarget(
            name: "MeetingBuddyApp",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain",
                "MeetingBuddyFeatures",
                "MeetingBuddyMedia",
                "MeetingBuddyPersistence",
                "MeetingBuddyTasks"
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
        ),
        .testTarget(
            name: "MeetingBuddyTasksTests",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain",
                "MeetingBuddyPersistence",
                "MeetingBuddyTasks",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MeetingBuddyMediaTests",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain",
                "MeetingBuddyMedia",
                "MeetingBuddyPersistence",
                "MeetingBuddyTasks",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MeetingBuddyFeaturesTests",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain",
                "MeetingBuddyFeatures"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
