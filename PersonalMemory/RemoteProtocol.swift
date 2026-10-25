import Foundation

struct RemoteInstructionRequest: Codable, Equatable {
    let version: Int
    let id: UUID
    let instruction: String
    let sentAt: Date
}

struct RemoteInstructionReceipt: Codable, Equatable {
    let version: Int
    let requestID: UUID
    let status: String
    let message: String
    let receivedAt: Date
}