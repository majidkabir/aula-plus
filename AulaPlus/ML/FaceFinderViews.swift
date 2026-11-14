import ImageIO
import Observation
import PhotosUI
import SwiftUI

/// Runs face finding: learns each child's face from their tagged photos, then checks photos.
@MainActor
@Observable
final class FaceFinding {
    static let shared = FaceFinding()
    /// While searching every album: (album number, album count).
    private(set) var allAlbums: (done: Int, total: Int)?

    /// Learn faces (from tagged photos, at most once a day) and check `photos`.
    static func learnAndScan(_ photos: [Media], children: [Child], data: DataStore) async {
        let index = FaceIndex.shared
        guard index.isEnabled, !children.isEmpty else { return }
        await learn(children: children, data: data)
        await index.scan(photos, children: children)
    }

    static func learn(children: [Child], data: DataStore) async {
        let index = FaceIndex.shared
        for c in children where index.referenceCount(c.id) < 8 {
            let tagged = data.media(album: .tagged(c))
            await tagged.load(maxAge: 86_400)
            await index.learn(c, from: tagged.value ?? [])
        }
    }

    /// Checks every album, newest first.
    func searchAllAlbums(children: [Child], data: DataStore) async {
        guard allAlbums == nil else { return }
        allAlbums = (0, 0)
        defer { allAlbums = nil }
        await Self.learn(children: children, data: data)
        await data.albums.load(maxAge: 3600)
        let albums = data.albums.value ?? []
        for (i, album) in albums.enumerated() {
            allAlbums = (i, albums.count)
            let media = data.media(album: album)
            await media.load(maxAge: 3600)
            await FaceIndex.shared.scan(media.value ?? [], children: children)
        }
    }
}

/// Small "found by face" mark on a photo or avatar.
struct FaceBadge: View {
    var size: CGFloat = 12
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.purple, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1))
            .accessibilityLabel(Text("Fundet med ansigtsgenkendelse"))
    }
}

/// "Lær fra Fotos": the parent picks photos of the child in the Photos app (the child's album
/// under People is quickest); the child's face is learned from them on the phone.
struct LearnFromPhotosButton: View {
    let child: Child
    @State private var items: [PhotosPickerItem] = []
    @State private var working = false
    @State private var result: String?

    var body: some View {
        PhotosPicker(selection: $items, maxSelectionCount: 60, matching: .images, photoLibrary: .shared()) {
            if working {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Lærer \(child.firstName)s ansigt …") }
            } else {
                Label("Lær fra Fotos", systemImage: "photo.on.rectangle.angled")
            }
        }
        .font(.subheadline.weight(.bold))
        .buttonStyle(.bordered)
        .tint(.purple)
        .disabled(working)
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            Task { await learn(picked) }
        }
        .alert(result ?? "", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func learn(_ picked: [PhotosPickerItem]) async {
        working = true
        defer { working = false; items = [] }
        var images: [CGImage] = []
        for item in picked {
            guard let data = try? await item.loadTransferable(type: Data.self), let img = Self.downsized(data) else { continue }
            images.append(img)
        }
        let n = await FaceIndex.shared.learn(child, fromPhotos: images)
        result = n > 0
            ? String(localized: "Lærte \(child.firstName)s ansigt fra \(n) billeder. Åbn albums eller tryk \"Søg i alle albums\" for at finde \(child.firstName).")
            : String(localized: "Fandt ikke \(child.firstName)s ansigt. Vælg flere billeder, hvor ansigtet ses tydeligt forfra.")
    }

    private static func downsized(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 1280]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

/// In a child's album: what face finding knows, and a button to search every album.
struct FindChildCard: View {
    let child: Child
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app
    private var faces: FaceIndex { FaceIndex.shared }
    private var finder: FaceFinding { FaceFinding.shared }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "face.smiling.inverse")
                .font(.title3.weight(.bold)).foregroundStyle(.purple)
                .frame(width: 40, height: 40)
                .background(Color.purple.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                if faces.hasReferences(child.id) {
                    Text("\(faces.found(child.id).count) billeder fundet på telefonen")
                        .font(.subheadline.weight(.bold))
                    Text("Billeder uden tag, hvor Aula+ genkender \(child.firstName). Markeret med ✦. Flere rigtige med \"Lær fra Fotos\": vælg billeder af \(child.firstName), fx fra Personer i Fotos.")
                        .font(.caption).foregroundStyle(.secondary)
                    LearnFromPhotosButton(child: child)
                    if let p = finder.allAlbums {
                        ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                        Text("Album \(p.done + 1) af \(max(p.total, 1))").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button {
                            let children = app.children
                            Task { await finder.searchAllAlbums(children: children, data: data) }
                        } label: {
                            Label("Søg i alle albums", systemImage: "magnifyingglass")
                                .font(.subheadline.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                } else {
                    Text("Find \(child.firstName) på billeder uden tag").font(.subheadline.weight(.bold))
                    Text("Aula+ lærer \(child.firstName)s ansigt fra billeder med tag. Har \(child.firstName) ingen, så åbn et billede og vælg \"Det er \(child.firstName)\" under ☺︎.")
                        .font(.caption).foregroundStyle(.secondary)
                    LearnFromPhotosButton(child: child)
                }
            }
            Spacer(minLength: 0)
        }
        .cardStyle(padding: 14)
    }
}
