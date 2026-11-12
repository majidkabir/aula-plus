import Foundation

extension AulaAPI {
    /// Replies in an existing thread.
    /// Request shape from the decompiled official app (`messaging.reply`).
    func reply(threadId: String, text: String) async throws {
        let body: [String: Any] = [
            "threadId": Int(threadId) ?? threadId,
            "message": [
                "text": Self.htmlFromPlainText(text),
                "attachmentIds": [Int](),
            ] as [String: Any],
            "commonInboxId": NSNull(),
            "bundleId": NSNull(),
        ]
        let _: Ignored = try await call("messaging.reply", body: body)
    }

    /// Downloads an attachment with the Aula session (cookies) to a temp file
    /// so it can be shown with Quick Look.
    func download(_ url: URL, suggestedName: String) async throws -> URL {
        var req = URLRequest(url: url)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        let (tmp, resp) = try await session.download(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw AulaError.http(code) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var name = suggestedName
            .replacingOccurrences(of: #"[\\/:*?"<>|\p{Cc}]"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(120))
        if name.isEmpty { name = "fil" }
        if (name as NSString).pathExtension.isEmpty {
            let ext = resp.suggestedFilename.map { ($0 as NSString).pathExtension } ?? url.pathExtension
            if !ext.isEmpty { name += ".\(ext)" }
        }
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Deletes downloaded attachments (they can be sensitive documents).
    static func clearDownloads() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("attachments"))
    }

    static func htmlFromPlainText(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return escaped
            .components(separatedBy: "\n\n")
            .map { "<p>" + $0.replacingOccurrences(of: "\n", with: "<br>") + "</p>" }
            .joined()
    }
}
