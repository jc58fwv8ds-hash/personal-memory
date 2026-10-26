import AppKit

/// Adds one note to Apple's Notes app, only after the user confirmed it (2026-10-26). macOS asks once whether this app
/// may control Notes; nothing is read from Notes and no existing note is changed.
@MainActor final class NotesWriter {
    /// Returns the new note's identifier.
    func save(title: String, body: String) throws -> String {
        let html = "<div><h1>\(Self.escapeHTML(title))</h1></div>"
            + body.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "<div>\($0.isEmpty ? "<br>" : Self.escapeHTML(String($0)))</div>" }.joined()
        let source = "tell application \"Notes\" to get id of (make new note with properties {name:\(Self.quote(title)), body:\(Self.quote(html))})"
        guard let script = NSAppleScript(source: source) else { throw CalendarFlowError.message("メモに保存する準備ができませんでした。") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            throw CalendarFlowError.message(number == -1743
                ? "メモへの保存が許可されていません。システム設定の「プライバシーとセキュリティ」→「オートメーション」で許可できます。"
                : "メモに保存できませんでした。\(error[NSAppleScript.errorMessage] as? String ?? "")")
        }
        return result.stringValue ?? "saved"
    }

    private static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
