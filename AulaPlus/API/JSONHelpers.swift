import Foundation

/// Aula is loose with types: ids arrive as numbers or strings, arrays contain
/// junk, text arrives as `{ "html": ... }` or a bare string. These wrappers keep
/// one odd field from failing a whole screen.

struct FlexString: Decodable, Hashable {
    let value: String
    init(_ v: String) { value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(Int(d)) }
        else { value = "" }
    }
}

struct FlexInt: Decodable, Hashable {
    let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let s = try? c.decode(String.self), let i = Int(s) { value = i }
        else if let d = try? c.decode(Double.self) { value = Int(d) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not an integer")
        }
    }
}

/// An array that silently drops elements it cannot decode.
struct Lossy<T: Decodable>: Decodable {
    let items: [T]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [T] = []
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) { out.append(v) }
            else { _ = try? c.decode(Skip.self) }
        }
        items = out
    }
}

private struct Skip: Decodable {
    init(from decoder: Decoder) throws {}
}

/// Rich text that is either `{ "html": "..." }` or a plain string.
struct HTMLField: Decodable {
    let html: String
    private enum K: String, CodingKey { case html }
    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: K.self) {
            html = (try? c.decode(String.self, forKey: .html)) ?? ""
        } else if let s = try? decoder.singleValueContainer().decode(String.self) {
            html = s
        } else {
            html = ""
        }
    }
}

enum AulaDate {
    static let copenhagen = TimeZone(identifier: "Europe/Copenhagen")!

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let naive: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
    ].map { pattern in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = copenhagen
        f.dateFormat = pattern
        return f
    }

    /// Parses offset, `Z` and naive timestamps (naive = Copenhagen time).
    static func parse(_ s: String?) -> Date? {
        guard var s, !s.isEmpty else { return nil }
        // "2026-03-01 09:00:00+0100" → "2026-03-01T09:00:00+01:00"
        if s.count > 10, s[s.index(s.startIndex, offsetBy: 10)] == " " {
            s.replaceSubrange(s.index(s.startIndex, offsetBy: 10)...s.index(s.startIndex, offsetBy: 10), with: "T")
        }
        s = s.replacingOccurrences(of: #"([+-]\d{2})(\d{2})$"#, with: "$1:$2", options: .regularExpression)
        if let d = isoFrac.date(from: s) ?? iso.date(from: s) { return d }
        for f in naive { if let d = f.date(from: s) { return d } }
        return nil
    }

    /// Presence times ("07:45:00", "2026-11-12T07:45:00") → "07:45".
    static func shortTime(_ s: String?) -> String? {
        guard let s, let r = s.range(of: #"\d{2}:\d{2}"#, options: .regularExpression) else { return nil }
        return String(s[r])
    }
}
