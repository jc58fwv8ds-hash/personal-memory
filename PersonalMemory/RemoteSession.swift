import Foundation
import Observation

@MainActor
@Observable
final class RemoteSession {
    var instruction = ""
    var statusMessage = "未接続"
    var pairingCode = ""
}