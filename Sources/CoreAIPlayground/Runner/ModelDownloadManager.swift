import Foundation
import Observation
import CryptoKit

/// Downloads `.aimodel` assets over the network into the app's sandbox
/// container (Application Support), with progress, cancel, resume, and optional
/// SHA-256 verification.
///
/// This is the mechanism that works *today*, while the app is running. For
/// App Store distribution where assets should download out-of-process (even
/// before first launch), see `ModelDownloaderExtension` and the Background
/// Assets section of the README — that path requires an app-extension target
/// and the `com.apple.developer.background-assets` entitlement.
@MainActor
@Observable
final class ModelDownloadManager {

    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double, receivedBytes: Int64, totalBytes: Int64)
        case verifying
        case finished(URL)
        case failed(String)

        var isActive: Bool {
            if case .downloading = self { return true }
            if case .verifying = self { return true }
            return false
        }
    }

    /// Observed per-model phase. Reading `phases[id]` in a view tracks updates.
    private(set) var phases: [ModelSpec.ID: Phase] = [:]

    @ObservationIgnored private var tasks: [ModelSpec.ID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var resumeData: [ModelSpec.ID: Data] = [:]
    @ObservationIgnored private var _session: URLSession?
    @ObservationIgnored private var delegate: DownloadDelegate?

    /// Memoized session wired to a delegate that forwards to this manager.
    private var session: URLSession {
        if let existing = _session { return existing }
        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = true
        config.waitsForConnectivity = true
        let delegate = DownloadDelegate(manager: self)
        self.delegate = delegate
        let created = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        _session = created
        return created
    }

    func phase(for model: ModelSpec) -> Phase { phases[model.id] ?? .idle }

    // MARK: - Storage

    /// `~/Library/Application Support/<bundle>/Models/<modelID>/` inside the sandbox.
    func modelDirectory(for model: ModelSpec) -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(model.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func destinationURL(for model: ModelSpec, suggested: String?) -> URL {
        let name = suggested.flatMap { $0.isEmpty ? nil : $0 } ?? "\(model.id).aimodel"
        return modelDirectory(for: model).appendingPathComponent(name)
    }

    /// Returns the on-disk asset if one was already downloaded for this model.
    func existingAsset(for model: ModelSpec) -> URL? {
        let dir = modelDirectory(for: model)
        let contents = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                     includingPropertiesForKeys: nil)) ?? []
        // Prefer an .aimodel, else the first non-hidden file.
        return contents.first { $0.pathExtension == "aimodel" }
            ?? contents.first { !$0.lastPathComponent.hasPrefix(".") }
    }

    // MARK: - Lifecycle

    func download(model: ModelSpec, from url: URL) {
        cancel(model: model)
        phases[model.id] = .downloading(fraction: 0, receivedBytes: 0, totalBytes: 0)
        let task: URLSessionDownloadTask
        if let data = resumeData[model.id] {
            task = session.downloadTask(withResumeData: data)
            resumeData[model.id] = nil
        } else {
            task = session.downloadTask(with: url)
        }
        task.taskDescription = model.id
        tasks[model.id] = task
        task.resume()
    }

    func cancel(model: ModelSpec) {
        guard let task = tasks[model.id] else { return }
        task.cancel { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                if let data { self.resumeData[model.id] = data }
                self.tasks[model.id] = nil
                if self.phases[model.id]?.isActive == true { self.phases[model.id] = .idle }
            }
        }
    }

    // MARK: - Delegate callbacks (invoked on MainActor)

    fileprivate func updateProgress(modelID: ModelSpec.ID, received: Int64, total: Int64) {
        let fraction = total > 0 ? Double(received) / Double(total) : 0
        phases[modelID] = .downloading(fraction: fraction, receivedBytes: received, totalBytes: total)
    }

    fileprivate func finish(modelID: ModelSpec.ID, tempURL: URL, suggestedName: String?) {
        guard let model = currentModel(for: modelID) else { return }
        tasks[modelID] = nil
        let destination = destinationURL(for: model, suggested: suggestedName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
        } catch {
            phases[modelID] = .failed("Couldn't save asset: \(error.localizedDescription)")
            return
        }

        if let expected = model.sha256 {
            phases[modelID] = .verifying
            verify(destination, expectedSHA256: expected) { [weak self] ok in
                Task { @MainActor in
                    self?.phases[modelID] = ok ? .finished(destination)
                        : .failed("Checksum mismatch — download may be corrupt.")
                }
            }
        } else {
            phases[modelID] = .finished(destination)
        }
    }

    fileprivate func fail(modelID: ModelSpec.ID, error: Error, resumeData data: Data?) {
        tasks[modelID] = nil
        if let data { resumeData[modelID] = data }
        // A user-initiated cancel surfaces as NSURLErrorCancelled — treat as idle.
        if (error as NSError).code == NSURLErrorCancelled {
            if phases[modelID]?.isActive == true { phases[modelID] = .idle }
        } else {
            phases[modelID] = .failed(error.localizedDescription)
        }
    }

    @ObservationIgnored private var modelLookup: [ModelSpec.ID: ModelSpec] = [:]
    /// The manager remembers the specs it's been asked to download so delegate
    /// callbacks (which only carry the task description) can resolve them.
    func register(_ model: ModelSpec) { modelLookup[model.id] = model }
    private func currentModel(for id: ModelSpec.ID) -> ModelSpec? { modelLookup[id] }

    private func verify(_ url: URL, expectedSHA256 expected: String, completion: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                completion(false); return
            }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            completion(hex.caseInsensitiveCompare(expected) == .orderedSame)
        }
    }
}

/// URLSession delegate that forwards progress/completion to the `@MainActor`
/// manager. Marked `@unchecked Sendable` because URLSession invokes it on its
/// own queue; it only hops back to the main actor.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var manager: ModelDownloadManager?
    init(manager: ModelDownloadManager) { self.manager = manager }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in
            manager?.updateProgress(modelID: id, received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        // The temp file is deleted when this method returns, so move it now,
        // synchronously, off a copy in a stable temp location.
        let stableTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: stableTemp)
        let suggested = downloadTask.response?.suggestedFilename
        Task { @MainActor in
            manager?.finish(modelID: id, tempURL: stableTemp, suggestedName: suggested)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error else { return }
        let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            manager?.fail(modelID: id, error: error, resumeData: resume)
        }
    }
}
