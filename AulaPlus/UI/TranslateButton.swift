import NaturalLanguage
import SwiftUI
#if canImport(Translation)
import Translation
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Small "Oversæt" button under Danish text. Shows the English text inline; tap again for the original.
/// Uses Apple's Translate (iOS 18+) when it has Danish, else Apple Intelligence on the phone. Nothing leaves the phone.
struct TranslateButton: View {
    let html: String
    @State private var english: String?
    @State private var showing = false
    @State private var busy = false
    @State private var failed: String?
    @State private var request = false   // runs Apple Translate (iOS 18+)

    var body: some View {
        let text = HTML.plainText(html).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 3, Self.isDanish(text) {
            VStack(alignment: .leading, spacing: 4) {
                if showing, let english {
                    Text(english).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Button { tap(text) } label: {
                    HStack(spacing: 4) {
                        if busy { ProgressView().controlSize(.mini) } else { Image(systemName: "translate") }
                        Text(failed.map { LocalizedStringKey($0) } ?? (showing ? "Vis original" : "Oversæt"))
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Color.brand)
                .disabled(busy)
                .accessibilityHint(Text("Viser teksten på engelsk"))
            }
            .modifier(AppleTranslate(request: $request, text: text) { result in
                busy = false
                if let result { english = result; showing = true } else { Task { await viaModel(text) } }
            })
        }
    }

    private func tap(_ text: String) {
        if showing { showing = false; return }
        if english != nil { showing = true; return }
        failed = nil
        busy = true
        if #available(iOS 18.0, *) {
            Task {
                let status = await LanguageAvailability().status(from: Locale.Language(identifier: "da"),
                                                                 to: Locale.Language(identifier: "en"))
                if status == .unsupported { await viaModel(text) }
                else { request = true }
            }
        } else {
            Task { await viaModel(text) }
        }
    }

    /// Apple Intelligence on the phone (Danish since iOS 26.1).
    private func viaModel(_ text: String) async {
        defer { busy = false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AIModel.onDevice {
            do {
                let session = LanguageModelSession(instructions:
                    "Translate the user's text from Danish to English. Keep names, dates, times and line breaks. Output only the translation.")
                english = try await session.respond(to: String(text.prefix(4000))).content
                showing = true
                return
            } catch {}
        }
        #endif
        failed = String(localized: "Oversættelse virker ikke på denne iPhone")
    }

    /// Danish, or Norwegian (the two are easy to mix up and Aula writes Danish).
    static func isDanish(_ text: String) -> Bool {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.danish, .norwegian, .english, .swedish, .german]
        r.processString(String(text.prefix(600)))
        return r.dominantLanguage == .danish || r.dominantLanguage == .norwegian
    }
}

/// Runs Apple's Translate when `request` is set; reports nil when it can't (then the caller tries Apple Intelligence).
private struct AppleTranslate: ViewModifier {
    @Binding var request: Bool
    let text: String
    let done: (String?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.translationTask(request ? TranslationSession.Configuration(source: .init(identifier: "da"), target: .init(identifier: "en")) : nil) { session in
                do {
                    let paragraphs = text.components(separatedBy: "\n")
                    var out: [String] = []
                    for p in paragraphs {
                        out.append(p.trimmingCharacters(in: .whitespaces).isEmpty ? p : try await session.translate(p).targetText)
                    }
                    await MainActor.run { done(out.joined(separator: "\n")); request = false }
                } catch {
                    await MainActor.run { done(nil); request = false }
                }
            }
        } else {
            content
        }
    }
}
