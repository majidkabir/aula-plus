import ImageIO
import SwiftUI
import UIKit

/// Photos cached by Aula id, not by URL. Aula's photo URLs are signed and expire, so a URL
/// cache misses (or fails) every time the list is refreshed; the photo itself never changes.
actor ImageStore {
    static let shared = ImageStore()

    private nonisolated let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 96 * 1024 * 1024
        return c
    }()
    private let dir: URL
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("aula-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dir = self.dir
        Task.detached(priority: .background) { Self.prune(dir, olderThanDays: 45) }
    }

    /// Already decoded and in memory: shown on the first frame, no flicker.
    nonisolated func memoryImage(_ key: String) -> UIImage? { memory.object(forKey: key as NSString) }

    /// Memory → disk → network. `maxPixel` downsizes (thumbnails); nil keeps full size.
    func image(key: String, url: URL?, maxPixel: CGFloat?) async -> UIImage? {
        if let m = memoryImage(key) { return m }
        let file = dir.appendingPathComponent(Self.fileName(key))
        if let data = try? Data(contentsOf: file), let img = Self.decode(data, maxPixel: maxPixel) {
            remember(img, key)
            return img
        }
        guard let url else { return nil }
        if let running = inflight[key] { return await running.value }
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let img = Self.decode(data, maxPixel: maxPixel) else { return nil }
            let stored = maxPixel == nil ? data : (img.jpegData(compressionQuality: 0.82) ?? data)
            try? stored.write(to: file, options: .atomic)
            return img
        }
        inflight[key] = task
        let img = await task.value
        inflight[key] = nil
        if let img { remember(img, key) }
        return img
    }

    private nonisolated func remember(_ img: UIImage, _ key: String) {
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        memory.setObject(img, forKey: key as NSString, cost: cost)
    }

    private static func fileName(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
    }

    /// Decodes (and downsizes) off the main thread with ImageIO.
    private static func decode(_ data: Data, maxPixel: CGFloat?) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel ?? 2800,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func prune(_ dir: URL, olderThanDays days: Double) {
        let fm = FileManager.default
        let limit = Date().addingTimeInterval(-days * 86_400)
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentAccessDateKey])) ?? []
        for f in files {
            let used = (try? f.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate ?? .distantPast
            if used < limit { try? fm.removeItem(at: f) }
        }
    }
}

/// An Aula photo from `ImageStore`: instant when cached, else loaded once and kept.
/// `onFailure` runs when it can't be loaded (typically: the signed URL has expired).
struct CachedImage<Placeholder: View>: View {
    let key: String
    let url: URL?
    var maxPixel: CGFloat? = 400
    var contentMode: ContentMode = .fill
    var onFailure: (() -> Void)? = nil
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?

    init(key: String, url: URL?, maxPixel: CGFloat? = 400, contentMode: ContentMode = .fill,
         onFailure: (() -> Void)? = nil, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.key = key
        self.url = url
        self.maxPixel = maxPixel
        self.contentMode = contentMode
        self.onFailure = onFailure
        self.placeholder = placeholder
        _image = State(initialValue: ImageStore.shared.memoryImage(key))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: "\(key)|\(url?.absoluteString ?? "")") {
            if image == nil { image = ImageStore.shared.memoryImage(key) }
            guard image == nil else { return }
            if let img = await ImageStore.shared.image(key: key, url: url, maxPixel: maxPixel) {
                image = img
            } else if !Task.isCancelled {
                onFailure?()
            }
        }
    }
}
