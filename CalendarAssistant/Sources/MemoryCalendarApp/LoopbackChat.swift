import Foundation

/// One JSON-mode chat with the local Ollama on 127.0.0.1 only: no redirects, no proxy, a capped answer.
enum LoopbackChat {
    static func json(system: String, user: String, model: String, maxTokens: Int = 2048) async throws -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
        request.httpMethod = "POST"; request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "stream": false, "think": false, "format": "json",
            "options": ["temperature": 0, "num_predict": maxTokens],
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]]
        ])
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 190
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: LoopbackOnlyDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CalendarFlowError.message("ローカルモデルが応答できません。Ollamaの起動とモデル名を確認してください。")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 131_072 else { throw CalendarFlowError.message("AIの回答が長すぎるため停止しました。") }
            data.append(byte)
        }
        struct Response: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        return try JSONDecoder().decode(Response.self, from: data).message.content
    }
}

private final class LoopbackOnlyDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
