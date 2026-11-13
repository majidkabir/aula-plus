import Photos
import SwiftUI
import UIKit

/// Saves downloaded gallery files to the Photos library (add-only permission).
enum PhotoSaver {
    enum Failure: LocalizedError {
        case denied
        var errorDescription: String? {
            String(localized: "Aula+ må ikke gemme i Fotos. Slå det til under Indstillinger → Aula+ → Fotos.")
        }
    }

    static func save(_ file: URL, isVideo: Bool) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: isVideo ? .video : .photo, fileURL: file, options: nil)
        }
    }
}

/// A downloaded file to hand to the share sheet.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// UIKit share sheet (opens straight away, unlike a ShareLink that needs a second tap).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
