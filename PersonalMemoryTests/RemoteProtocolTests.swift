import Foundation
import Testing
@testable import PersonalMemory

@Test func requestRoundTrip() throws {
    let request = RemoteInstructionRequest(
        version: 1,
        id: UUID(),
        instruction: "画面を確認して",
        sentAt: Date(timeIntervalSince1970: 1_000)
    )
    let data = try JSONEncoder().encode(request)
    #expect(try JSONDecoder().decode(RemoteInstructionRequest.self, from: data) == request)
}