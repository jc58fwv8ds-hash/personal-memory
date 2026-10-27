// swift-tools-version: 6.2
import PackageDescription

// Host-side verification of the same persistence sources used by the iPhone app.
let package = Package(name: "PersonalMemory", platforms: [.macOS(.v14)], products: [
    .library(name: "SessionDomain", targets: ["SessionDomain"])
], targets: [
    .target(name: "SessionDomain", path: "SessionDomain"),
    .testTarget(name: "SessionDomainTests", dependencies: ["SessionDomain"], path: "SessionDomainTests"),
    .target(name: "RecordingSupport", path: "SharedAudio", exclude: ["RecordingsView.swift"]),
    .testTarget(name: "RecordingSupportTests", dependencies: ["RecordingSupport"], path: "RecordingSupportTests"),
    .target(name: "WatchCaptureControl", path: "WatchMemory",
        exclude: ["WatchMemoryApp.swift", "WatchRecorder.swift", "WatchRecordingEngine.swift", "WatchTransfer.swift"],
        sources: ["RecordingCancellation.swift"]),
    .target(name: "PersonalMemory", dependencies: ["SessionDomain"], path: "PersonalMemory",
        exclude: ["ContentView.swift", "DesignSystem.swift", "Info.plist", "NearbyChunkSender.swift", "PersonalMemoryApp.swift", "RemoteProtocol.swift", "RemoteSession.swift", "WatchCaptureReceiver.swift"],
        sources: ["MemoryCaptureModel.swift", "MemoryEventModel.swift", "DailyMemoryModel.swift", "MemoryEventStore.swift", "CaptureAudioInbox.swift", "SessionChunkInbox.swift"]),
    .testTarget(name: "PersonalMemoryTests", dependencies: ["PersonalMemory", "SessionDomain", "WatchCaptureControl"], path: "PersonalMemoryTests",
        exclude: ["RemoteProtocolTests.swift"], sources: ["MemoryModelTests.swift", "MemoryEventStoreTests.swift", "CaptureAudioInboxTests.swift", "RecordingCancellationTests.swift", "SessionChunkInboxPiecesTests.swift", "RemoveAudioTests.swift"])
])
