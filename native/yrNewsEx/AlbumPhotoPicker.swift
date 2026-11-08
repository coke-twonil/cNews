import SwiftUI
import Photos

struct PhotoAlbum: Identifiable, @unchecked Sendable {
    let id: String
    let title: String
    let assets: [PHAsset]
}
struct AlbumPhotoPicker: View {
    let limit: Int
    let onDone: ([PHAsset]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [PhotoAlbum] = []
    @State private var selected: [PHAsset] = []
    @State private var loading = true
    @State private var denied = false
    @State private var limited = false
    var body: some View {
        NavigationStack {
            Group {
                if loading { ProgressView("Loading photos…") }
                else if denied {
                    VStack(spacing: 16) {
                        Text("未獲允許讀取相片。請到 iPhone 設定允許相片存取，再重新開啟相簿。")
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }.padding(24)
                } else if let library = albums.first {
                    PhotoAlbumGrid(album: library, limit: limit, selected: $selected, onDone: { onDone(selected) }, directLibrary: true)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black).toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                if loading || denied { ReaderHeader(title: "圖片庫") { Button("取消") { dismiss() }.frame(minHeight: 44) } right: { EmptyView() } }
            }
        }.task { await loadAlbums() }
    }
    func loadAlbums() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard !Task.isCancelled else { return }
        limited = status == .limited
        guard status == .authorized || limited else { denied = true; loading = false; return }
        albums = await Task.detached {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            func items(_ result: PHFetchResult<PHAsset>) -> [PHAsset] { var assets: [PHAsset] = []; result.enumerateObjects { asset, _, _ in assets.append(asset) }; return assets }
            let result = [PhotoAlbum(id: "all", title: "最近項目", assets: items(PHAsset.fetchAssets(with: options)))]
            return result
        }.value
        loading = false
    }
}
struct PhotoAlbumGrid: View {
    let album: PhotoAlbum
    let limit: Int
    @Binding var selected: [PHAsset]
    let onDone: () -> Void
    var directLibrary = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
                ForEach(album.assets, id: \.localIdentifier) { asset in
                    let number = selected.firstIndex { $0.localIdentifier == asset.localIdentifier }
                    Button {
                        if let number { selected.remove(at: number) }
                        else if selected.count < limit { selected.append(asset) }
                    } label: {
                        PhotoAssetThumbnail(asset: asset).aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .bottomTrailing) {
                                if let number { Text("\(number+1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 23, height: 23).background(.blue, in: Circle()).padding(4) }
                            }.opacity(number == nil && selected.count >= limit ? 0.4 : 1)
                    }.buttonStyle(.plain).accessibilityLabel("Photo \(album.assets.firstIndex { $0.localIdentifier == asset.localIdentifier }.map { $0+1 } ?? 0)").accessibilityValue(number == nil ? "Not selected" : "Selected")
                }
            }
            Text("\(album.assets.count) 張照片").font(.footnote).foregroundStyle(.secondary).padding(20)
        }.defaultScrollAnchor(.top).background(.black).toolbar(.hidden, for: .navigationBar).navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            ReaderHeader(title: directLibrary ? "圖片庫" : album.title) {
                if directLibrary { Button("取消") { dismiss() }.frame(minHeight: 44) }
                else { ReaderBack(title: "照片") { dismiss() } }
            } right: {
                Button("完成", action: onDone).frame(minHeight: 44).disabled(selected.isEmpty)
            }
        }
    }
}
struct PhotoAssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var request = PHInvalidImageRequestID
    @State private var active = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.12)
                if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
            }
        }.onAppear {
            active = true
            let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .opportunistic
            request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 240, height: 240), contentMode: .aspectFill, options: options) { image, _ in
                Task { @MainActor in if active { self.image = image } }
            }
        }.onDisappear { active = false; PHImageManager.default().cancelImageRequest(request) }
    }
}
/// A cancelled iCloud/image request must not append a late photo or keep a task alive.
final class PhotoAssetDataRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request = PHInvalidImageRequestID
    private var continuation: CheckedContinuation<Data, Error>?
    private var cancelled = false
    func load(_ asset: PHAsset) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation; lock.unlock()
                let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .highQualityFormat; options.version = .current
                let id = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                    if let data { self.finish(.success(data)) }
                    else if info?[PHImageCancelledKey] as? Bool == true { self.finish(.failure(CancellationError())) }
                    else { self.finish(.failure((info?[PHImageErrorKey] as? Error) ?? PhotoPreparation.PhotoError.invalid)) }
                }
                lock.lock(); request = id; let stop = cancelled; lock.unlock()
                if stop { PHImageManager.default().cancelImageRequest(id) }
            }
        } onCancel: { self.cancel() }
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock(); let handler = continuation; continuation = nil; lock.unlock()
        handler?.resume(with: result)
    }
    private func cancel() {
        lock.lock(); cancelled = true; let id = request; let handler = continuation; continuation = nil; lock.unlock()
        PHImageManager.default().cancelImageRequest(id); handler?.resume(throwing: CancellationError())
    }
}
