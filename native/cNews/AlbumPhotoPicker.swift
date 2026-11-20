import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The system picker displays the whole library even when direct PhotoKit access
/// is limited. Only the photos the user selects are delivered to cNews.
struct AlbumPhotoPicker: UIViewControllerRepresentable {
    let limit: Int
    let onDone: ([PHPickerResult]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = max(1, min(3, limit))
        config.selection = .ordered
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ view: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onDone: ([PHPickerResult]) -> Void
        init(onDone: @escaping ([PHPickerResult]) -> Void) { self.onDone = onDone }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onDone(results)
        }
    }
}

/// Cancel iCloud imports and ignore callbacks arriving after cancellation.
final class PhotoAssetDataRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: Progress?
    private var continuation: CheckedContinuation<Data, Error>?
    private var cancelled = false
    func load(_ result: PHPickerResult) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation; lock.unlock()
                let provider = result.itemProvider
                guard let type = provider.registeredTypeIdentifiers.first(where: {
                    UTType($0)?.conforms(to: .image) == true
                }) else { self.finish(.failure(PhotoPreparation.PhotoError.invalid)); return }
                let work = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    if let data { self.finish(.success(data)) }
                    else { self.finish(.failure(error ?? PhotoPreparation.PhotoError.invalid)) }
                }
                lock.lock(); progress = work; let stop = cancelled; lock.unlock()
                if stop { work.cancel() }
            }
        } onCancel: { self.cancel() }
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock(); let handler = continuation; continuation = nil; lock.unlock()
        handler?.resume(with: result)
    }
    private func cancel() {
        lock.lock(); cancelled = true; let work = progress; let handler = continuation; continuation = nil; lock.unlock()
        work?.cancel(); handler?.resume(throwing: CancellationError())
    }
}
