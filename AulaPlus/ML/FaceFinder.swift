import CoreML
import Observation
import SwiftUI
import Vision

/// Finds faces in a photo and turns each into a 128-number "faceprint" with MobileFaceNet
/// (sirius-ai/MobileFaceNet_TF, Apache-2.0). Everything runs on the phone.
actor FaceEngine {
    static let shared = FaceEngine()

    struct Face {
        let embedding: [Float]
        /// Share of the photo's width the face takes (bigger = more reliable).
        let size: CGFloat
    }

    private var model: VNCoreMLModel?
    private var loaded = false

    private func coreModel() -> VNCoreMLModel? {
        if !loaded {
            loaded = true
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            model = (try? MobileFaceNet(configuration: cfg)).flatMap { try? VNCoreMLModel(for: $0.model) }
        }
        return model
    }

    /// Faces at least ~36 px wide, biggest first.
    func faces(in image: CGImage) -> [Face] {
        let request = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let width = CGFloat(image.width)
        return (request.results ?? [])
            .filter { $0.boundingBox.width * width >= 36 }
            .sorted { $0.boundingBox.width > $1.boundingBox.width }
            .prefix(12)
            .compactMap { obs in
                guard let crop = Self.aligned(image, obs), let e = embed(crop) else { return nil }
                return Face(embedding: e, size: obs.boundingBox.width)
            }
    }

    private func embed(_ face: CGImage) -> [Float]? {
        guard let model = coreModel() else { return nil }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        try? VNImageRequestHandler(cgImage: face, orientation: .up).perform([request])
        guard let array = (request.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue,
              array.count > 0 else { return nil }
        var v = (0..<array.count).map { Float(truncating: array[$0]) }
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        for i in v.indices { v[i] /= norm }
        return v
    }

    /// 112×112 crop with the eyes level and where MobileFaceNet expects them
    /// (ArcFace layout: eye centres at (38.3, 51.7) and (73.5, 51.5)). Falls back to the box.
    static func aligned(_ image: CGImage, _ obs: VNFaceObservation) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        let box = VNImageRectForNormalizedRect(obs.boundingBox, image.width, image.height) // y-up
        var mid = CGPoint(x: box.midX, y: box.midY + box.height * 0.12)
        var angle: CGFloat = 0
        var scale = 112 / (box.width * 1.05)
        if let l = obs.landmarks?.leftPupil?.pointsInImage(imageSize: size).first,
           let r = obs.landmarks?.rightPupil?.pointsInImage(imageSize: size).first {
            let (a, b) = l.x < r.x ? (l, r) : (r, l)
            let d = hypot(b.x - a.x, b.y - a.y)
            if d > 4 {
                angle = atan2(b.y - a.y, b.x - a.x)
                scale = 35.2 / d
                mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            }
        }
        guard let ctx = CGContext(data: nil, width: 112, height: 112, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(gray: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 112, height: 112))
        // Core Graphics is y-up like Vision: eyes go to y = 112 − 51.6.
        ctx.translateBy(x: 55.9, y: 60.4)
        ctx.rotate(by: -angle)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -mid.x, y: -mid.y)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }
}

/// Which photos show my children, worked out on the phone. The faceprints of other people
/// are never kept: only each photo's similarity to my own children is stored.
@MainActor
@Observable
final class FaceIndex {
    static let shared = FaceIndex()

    /// Similarity (average of the best 3 matches against the child's reference faces) that counts as a match.
    static let threshold: Float = 0.50

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "faceFinder") }
    }
    /// Photos being checked right now (for the progress line).
    private(set) var scanning: (done: Int, total: Int)?
    private(set) var learning = false

    private struct Store: Codable {
        var refs: [Int: [[Float]]] = [:]          // child id → the child's own reference faces
        var refsFrom: [Int: [Int]] = [:]          // child id → photo ids the references came from
        var scores: [Int: [Int: Float]] = [:]     // photo id → child id → similarity
        var version: Int = 0                      // bumps when references change; old scores are redone
        var scoredWith: [Int: Int] = [:]          // photo id → version it was scored with
        var rejected: [Int: Set<Int>] = [:]       // child id → photos the user said aren't them
        var found: [Int: [Media]] = [:]           // child id → matching photos (for the child's album)
    }

    private var store = Store()
    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("faces.json")
    }()
    private var saveTask: Task<Void, Never>?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "faceFinder") as? Bool ?? true
        if let data = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Store.self, from: data) { store = s }
    }

    // MARK: Questions the UI asks

    func hasReferences(_ childId: Int) -> Bool { (store.refs[childId]?.count ?? 0) > 0 }
    func referenceCount(_ childId: Int) -> Int { store.refs[childId]?.count ?? 0 }

    /// Found by face (not tagged by staff), and not rejected by the user.
    func isFaceMatch(_ m: Media, _ childId: Int) -> Bool {
        guard isEnabled, !m.isTagged(childId), !(store.rejected[childId]?.contains(m.id) ?? false) else { return false }
        return (store.scores[m.id]?[childId] ?? 0) >= Self.threshold
    }

    /// Tagged, or found by face.
    func shows(_ m: Media, _ childId: Int) -> Bool { m.isTagged(childId) || isFaceMatch(m, childId) }

    /// Photos found by face for the child's own album, newest scan first.
    func found(_ childId: Int) -> [Media] {
        guard isEnabled else { return [] }
        let rejected = store.rejected[childId] ?? []
        return (store.found[childId] ?? []).filter { !rejected.contains($0.id) && isFaceMatch($0, childId) }
    }

    // MARK: Learning a child's face

    /// Reference faces from photos the child is tagged in (one face only, so it's surely them).
    func learn(_ child: Child, from tagged: [Media]) async {
        guard isEnabled, !learning else { return }
        let have = Set(store.refsFrom[child.id] ?? [])
        let todo = tagged.filter { !$0.isVideo && !have.contains($0.id) }.prefix(40)
        guard !todo.isEmpty, (store.refs[child.id]?.count ?? 0) < 25 else { return }
        learning = true
        defer { learning = false }
        var added = 0
        for m in todo {
            guard let image = await Self.image(m) else { continue }
            let faces = await FaceEngine.shared.faces(in: image)
            store.refsFrom[child.id, default: []].append(m.id)
            if faces.count == 1, let f = faces.first, f.size > 0.06 {
                store.refs[child.id, default: []].append(f.embedding)
                added += 1
            }
            if (store.refs[child.id]?.count ?? 0) >= 25 { break }
        }
        if added > 0 { store.version += 1 }
        save()
    }

    /// "Det er Emma": the biggest face in this photo becomes one of the child's reference faces.
    func confirm(_ m: Media, is child: Child) async -> Bool {
        guard let image = await Self.image(m), let face = await FaceEngine.shared.faces(in: image).first else { return false }
        store.refs[child.id, default: []].append(face.embedding)
        store.refsFrom[child.id, default: []].append(m.id)
        store.rejected[child.id]?.remove(m.id)
        store.version += 1
        save()
        return true
    }

    /// "Ikke Emma".
    func reject(_ m: Media, isNot childId: Int) {
        store.rejected[childId, default: []].insert(m.id)
        save()
    }

    // MARK: Checking photos

    /// Checks photos not yet scored against the current reference faces. Runs one photo at a time.
    func scan(_ media: [Media], children: [Child]) async {
        guard isEnabled else { return }
        let kids = children.filter { hasReferences($0.id) }
        guard !kids.isEmpty, scanning == nil else { return }
        let todo = media.filter { !$0.isVideo && store.scoredWith[$0.id] != store.version }
        guard !todo.isEmpty else { return }
        scanning = (0, todo.count)
        defer { scanning = nil; save() }
        for (i, m) in todo.enumerated() {
            if Task.isCancelled || !isEnabled { break }
            if let image = await Self.image(m) {
                let faces = await FaceEngine.shared.faces(in: image)
                var row: [Int: Float] = [:]
                for kid in kids { row[kid.id] = Self.similarity(faces, store.refs[kid.id] ?? []) }
                store.scores[m.id] = row
                store.scoredWith[m.id] = store.version
                for kid in kids where (row[kid.id] ?? 0) >= Self.threshold && !m.isTagged(kid.id) {
                    var list = store.found[kid.id] ?? []
                    list.removeAll { $0.id == m.id }
                    list.insert(m, at: 0)
                    store.found[kid.id] = Array(list.prefix(1000))
                }
            }
            scanning = (i + 1, todo.count)
            if i % 20 == 19 { save() }
        }
    }

    /// Removes everything: reference faces, scores and found photos.
    func eraseAll() {
        store = Store()
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: Helpers

    /// Best face in the photo against the child: mean of its 3 highest cosine similarities.
    private static func similarity(_ faces: [FaceEngine.Face], _ refs: [[Float]]) -> Float {
        guard !refs.isEmpty else { return 0 }
        var best: Float = 0
        for f in faces {
            let sims = refs.map { r in zip(f.embedding, r).reduce(Float(0)) { $0 + $1.0 * $1.1 } }.sorted(by: >)
            let top = sims.prefix(3)
            best = max(best, top.reduce(0, +) / Float(top.count))
        }
        return best
    }

    private static func image(_ m: Media) async -> CGImage? {
        await ImageStore.shared.image(key: "m\(m.id)", url: m.scanURL ?? m.fullURL ?? m.thumbURL, maxPixel: 1280)?.cgImage
    }

    private func save() {
        saveTask?.cancel()
        let snapshot = store
        let file = self.file
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: file, options: [.atomic, .completeFileProtection])
        }
    }
}
