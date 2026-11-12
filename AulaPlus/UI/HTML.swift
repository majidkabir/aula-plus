import SwiftUI
import UIKit

enum HTML {
    private static let entities: [String: String] = [
        "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
        "&#39;": "'", "&apos;": "'", "&aelig;": "æ", "&oslash;": "ø", "&aring;": "å",
        "&AElig;": "Æ", "&Oslash;": "Ø", "&Aring;": "Å", "&ndash;": "–", "&mdash;": "—",
        "&hellip;": "…",
    ]

    /// Fast tag strip for list previews.
    static func plainText(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"<(br|/p|/div|/li)[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: #"&#(\d+);"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n\s*\n+"#, with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor private static var cache: [String: AttributedString] = [:]

    /// Full HTML → AttributedString keeping bold, italic and links. Aula's colours
    /// and fonts are dropped so text follows Dynamic Type and dark mode.
    @MainActor
    static func attributed(_ html: String) -> AttributedString {
        if let hit = cache[html] { return hit }
        let wrapped = "<html><head><meta charset=\"utf-8\"></head><body>\(html)</body></html>"
        guard let data = wrapped.data(using: .utf8),
              let ns = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)
        else { return AttributedString(plainText(html)) }

        let string = ns.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = (ns.string as NSString).range(of: string).location
        var out = AttributedString(string)
        let full = NSRange(location: 0, length: ns.length)
        ns.enumerateAttributes(in: full) { attrs, nsRange, _ in
            let shifted = NSRange(location: nsRange.location - (offset == NSNotFound ? 0 : offset), length: nsRange.length)
            guard shifted.location >= 0,
                  shifted.location + shifted.length <= (string as NSString).length,
                  let range = Range(shifted, in: out) else { return }
            if let font = attrs[.font] as? UIFont {
                let t = font.fontDescriptor.symbolicTraits
                var intent: InlinePresentationIntent = []
                if t.contains(.traitBold) { intent.insert(.stronglyEmphasized) }
                if t.contains(.traitItalic) { intent.insert(.emphasized) }
                if !intent.isEmpty { out[range].inlinePresentationIntent = intent }
            }
            if let link = attrs[.link] as? URL { out[range].link = link }
            else if let link = attrs[.link] as? String, let url = URL(string: link) { out[range].link = url }
        }
        cache[html] = out
        return out
    }
}

/// Renders Aula HTML as native, selectable text with working links.
struct HTMLText: View {
    let html: String
    @State private var text: AttributedString?

    var body: some View {
        Group {
            if let text { Text(text) } else { Text(HTML.plainText(html)) }
        }
        .textSelection(.enabled)
        .tint(Color.brand)
        .task(id: html) { text = HTML.attributed(html) }
    }
}
