import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which Apple model reads the texts.
/// iOS 27: Apple's bigger model on Private Cloud Compute (Apple's servers; nothing is stored or seen by Apple)
/// when the user allows it and the daily quota isn't used up. Otherwise the model on the phone.
enum AIModel {
    static let cloudKey = "ai.useCloud"

    /// User setting, on by default.
    static var cloudAllowed: Bool {
        get { UserDefaults.standard.object(forKey: cloudKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: cloudKey) }
    }

    /// Private Cloud Compute needs Apple's managed entitlement (com.apple.developer.private-cloud-compute).
    /// Without it iOS 27.0.1 doesn't throw: FoundationModels hits an assertion and the app crashes (build 40).
    /// So it stays off until the entitlement is granted and Info.plist sets AulaPlusPrivateCloudCompute = YES.
    static let hasEntitlement = Bundle.main.object(forInfoDictionaryKey: "AulaPlusPrivateCloudCompute") as? Bool == true

    /// The device can use Private Cloud Compute at all (iOS 27, Apple Intelligence on, entitlement granted).
    static var cloudSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *), hasEntitlement { return PrivateCloudComputeLanguageModel().isAvailable }
        #endif
        return false
    }

    static var cloud: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *), hasEntitlement, cloudAllowed {
            let m = PrivateCloudComputeLanguageModel()
            return m.isAvailable && !m.quotaUsage.isLimitReached
        }
        #endif
        return false
    }

    static var onDevice: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let m = SystemLanguageModel.default
            guard case .available = m.availability else { return false }
            return m.supportsLocale(Locale(identifier: "da_DK"))
        }
        #endif
        return false
    }

    static var isAvailable: Bool { cloud || onDevice }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension AIModel {
    /// Runs `body` with the best model; if the cloud call fails (network, quota, language), tries the phone's model.
    static func run<T>(instructions: String, _ body: (LanguageModelSession) async throws -> T) async throws -> T {
        if #available(iOS 27.0, *), cloud {
            do {
                return try await body(LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions))
            } catch {
                guard onDevice else { throw error }
            }
        }
        return try await body(LanguageModelSession(instructions: instructions))
    }
}
#endif
