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
            name: "MeetingBuddyAI",
            targets: ["MeetingBuddyAI"]
        ),
        .library(
            name: "MeetingBuddyFeatures",
            targets: ["MeetingBuddyFeatures"]
        ),
        .library(
            name: "MeetingBuddyAutomation",
            targets: ["MeetingBuddyAutomation"]
        ),
        .executable(
            name: "MeetingBuddyApp",
            targets: ["MeetingBuddyApp"]
        ),
        .executable(
            name: "meetingbuddy-cli",
            targets: ["MeetingBuddyCLI"]
        ),
        .executable(
            name: "meetingbuddy-mcp",
            targets: ["MeetingBuddyMCP"]
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
            name: "MeetingBuddyAI",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain",
                "MeetingBuddyMedia"
            ]
        ),
        .target(
            name: "MeetingBuddyFeatures",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyDomain"
            ]
        ),
        .target(
            name: "MeetingBuddyAutomation",
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
                "MeetingBuddyAI",
                "MeetingBuddyMedia",
                "MeetingBuddyPersistence",
                "MeetingBuddyTasks"
            ]
        ),
        .executableTarget(
            name: "MeetingBuddyCLI",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyAutomation",
                "MeetingBuddyDomain",
                "MeetingBuddyPersistence"
            ]
        ),
        .executableTarget(
            name: "MeetingBuddyMCP",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyAutomation",
                "MeetingBuddyDomain",
                "MeetingBuddyPersistence"
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
            name: "MeetingBuddyAITests",
            dependencies: [
                "MeetingBuddyAI",
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
        ),
        .testTarget(
            name: "MeetingBuddyAutomationTests",
            dependencies: [
                "MeetingBuddyApplication",
                "MeetingBuddyAutomation",
                "MeetingBuddyDomain",
                "MeetingBuddyPersistence",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
