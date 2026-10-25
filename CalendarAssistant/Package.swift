// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "MemoryCalendar", platforms: [.macOS(.v14)], products: [
    .executable(name: "MemoryCalendar", targets: ["MemoryCalendarApp"])
], dependencies: [
    // Named explicitly: otherwise the identity is the folder name, and a clone named personal-memory would not resolve.
    .package(name: "PersonalMemory", path: "..")
], targets: [
    .target(name: "CalendarDomain", dependencies: [.product(name: "SessionDomain", package: "PersonalMemory")]),
    .executableTarget(name: "MemoryCalendarApp", dependencies: ["CalendarDomain"]),
    .testTarget(name: "CalendarDomainTests", dependencies: ["CalendarDomain"])
])
