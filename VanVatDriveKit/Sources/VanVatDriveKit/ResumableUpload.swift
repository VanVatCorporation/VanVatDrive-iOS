import Foundation
import Observation

/// One chunked, resumable upload: POST /uploads, PUT chunks (Upload-Offset), POST /complete.
/// After a network error it asks the server how far it got and continues from there.
public enum ResumableUpload {
    public static func run(client: DriveClient, fileURL: URL, parentId: String?, name: String? = nil, mimeType: String? = nil,
                           progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> DriveNode {
        let size = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let session = try await client.createUpload(parentId: parentId, name: name ?? fileURL.lastPathComponent, size: size, mimeType: mimeType)

        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            var offset = session.received
            var attempts = 0
            while offset < size {
                try Task.checkCancellation()
                let length = Int(min(Int64(session.chunkSize), size - offset))
                try handle.seek(toOffset: UInt64(offset))
                guard let chunk = try handle.read(upToCount: length), !chunk.isEmpty else {
                    throw DriveError(status: 0, code: "read", message: "Could not read the file.")
                }
                do {
                    let base = offset
                    let result = try await client.putChunk(uploadId: session.uploadId, offset: offset, data: chunk) { sent in progress(base + sent) }
                    switch result {
                    case .ok(let newOffset): offset = newOffset; attempts = 0
                    case .mismatch(let received): offset = received       // the server knows better
                    }
                    progress(offset)
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    if error is DriveError { throw error }                 // real server answer (quota, forbidden...)
                    attempts += 1
                    if attempts > 5 { throw error }
                    try await Task.sleep(nanoseconds: UInt64(attempts) * 800_000_000)
                    offset = try await client.uploadReceived(uploadId: session.uploadId)
                }
            }
            return try await client.completeUpload(uploadId: session.uploadId)
        } catch {
            // Detached: this task may already be cancelled, and the cleanup call must still go out.
            Task.detached { await client.cancelUpload(uploadId: session.uploadId) }
            throw error
        }
    }
}

/// Observable upload queue for the UI: two files at a time, progress, cancel, retry.
@MainActor @Observable
public final class UploadQueue {
    public enum State: Equatable, Sendable { case queued, uploading, done, failed(String), canceled }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let size: Int64
        public var loaded: Int64
        public var state: State
        /// Server error code of a failed upload (quota_exceeded, daily_upload_limit...), so the UI can offer an upgrade.
        public var errorCode: String?
        public let parentId: String?
        let fileURL: URL
        let deleteAfter: Bool
    }

    public private(set) var items: [Item] = []
    /// Called on the main actor after a file landed in the Drive.
    public var onItemFinished: (@MainActor (DriveNode) -> Void)?

    private let client: DriveClient
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let maxParallel = 2

    public init(client: DriveClient) { self.client = client }

    public var activeCount: Int { items.filter { $0.state == .queued || $0.state == .uploading }.count }

    /// `copiedIntoSandbox`: true when the files are temp copies the queue may delete afterwards.
    public func add(fileURLs: [URL], parentId: String?, copiedIntoSandbox: Bool = true) {
        for url in fileURLs {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            items.append(Item(id: UUID(), name: url.lastPathComponent, size: size, loaded: 0, state: .queued, errorCode: nil,
                              parentId: parentId, fileURL: url, deleteAfter: copiedIntoSandbox))
        }
        pump()
    }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        if let i = index(id), items[i].state == .queued { items[i].state = .canceled; cleanup(items[i]) }
    }

    public func retry(_ id: UUID) {
        guard let i = index(id), case .failed = items[i].state else { return }
        items[i].state = .queued
        items[i].errorCode = nil
        items[i].loaded = 0
        pump()
    }

    public func clearFinished() {
        items.removeAll { $0.state != .queued && $0.state != .uploading }
    }

    private func index(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    private func cleanup(_ item: Item) {
        if item.deleteAfter { try? FileManager.default.removeItem(at: item.fileURL) }
    }

    private func pump() {
        while tasks.count < maxParallel, let next = items.first(where: { $0.state == .queued && tasks[$0.id] == nil }) {
            let id = next.id
            if let i = index(id) { items[i].state = .uploading }
            tasks[id] = Task { [weak self] in
                guard let self else { return }
                await self.run(id)
            }
        }
    }

    private func run(_ id: UUID) async {
        guard let i = index(id) else { return }
        let item = items[i]
        do {
            let node = try await ResumableUpload.run(client: client, fileURL: item.fileURL, parentId: item.parentId) { [weak self] sent in
                Task { @MainActor in self?.setLoaded(id, sent) }
            }
            if let j = index(id) { items[j].state = .done; items[j].loaded = items[j].size }
            cleanup(item)
            onItemFinished?(node)
        } catch is CancellationError {
            if let j = index(id) { items[j].state = .canceled }
            cleanup(item)
        } catch {
            if Task.isCancelled {
                if let j = index(id) { items[j].state = .canceled }
                cleanup(item)
            } else if let j = index(id) {
                items[j].state = .failed(error.localizedDescription)
                items[j].errorCode = (error as? DriveError)?.code
            }
        }
        tasks[id] = nil
        pump()
    }

    private func setLoaded(_ id: UUID, _ value: Int64) {
        guard let i = index(id), items[i].state == .uploading else { return }
        items[i].loaded = min(items[i].size, value)
    }
}
