import NaturalLanguage
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Small "Oversæt" button under Danish text: opens Apple's translation sheet (English or the phone's language).
/// Shown only when the text is Danish; translation runs on the phone.
struct TranslateButton: View {
    let html: String
    @State private var show = false

    var body: some View {
        let text = HTML.plainText(html).trimmingCharacters(in: .whitespacesAndNewlines)
        if #available(iOS 17.4, *), text.count > 3, Self.isDanish(text) {
            Button { show = true } label: {
                Label("Oversæt", systemImage: "translate")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .tint(Color.brand)
            .translationPresentation(isPresented: $show, text: text)
            .accessibilityHint(Text("Viser teksten på engelsk"))
        }
    }

    static func isDanish(_ text: String) -> Bool {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.danish, .english, .norwegian, .swedish, .german]
        r.processString(String(text.prefix(600)))
        return r.dominantLanguage == .danish
    }
}
