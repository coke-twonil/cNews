import Foundation

/// Serial atomic writes, coalescing pending snapshots while a write is in progress.
/// Encoding large article/image caches must never block UI input or photo selection.
final class SnapshotFileWriter: @unchecked Sendable {
    private let file: URL
    private let queue = DispatchQueue(label: "org.cnews.snapshot-writer", qos: .utility)
    private let lock = NSLock()
    private var pending: (ReaderSnapshot, @Sendable (String) -> Void)?
    private var running = false
    init(file: URL) { self.file = file }
    func schedule(_ snapshot: ReaderSnapshot, onError: @escaping @Sendable (String) -> Void) {
        lock.lock()
        pending = (snapshot, onError)
        let start = !running
        running = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }
    private func drain() {
        while true {
            lock.lock()
            guard let (snapshot, onError) = pending else { running = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            autoreleasepool {
                do {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
                } catch { onError(error.localizedDescription) }
            }
        }
    }
    /// Used by tests to await persistence, never by the UI.
    func flush() { queue.sync {} }
}
