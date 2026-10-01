import AppKit
import Foundation

/// Downloads, verifies, and installs an update over the running app, then relaunches it.
///
/// Order: preflight (install location, key, assets) → signature asset → disk image (progress) →
/// size, GitHub checksum, Ed25519 signature → mount with `hdiutil -nobrowse` (Finder never sees
/// it) → copy the app out → bundle identifier, version, minimum macOS, code signature → swap the
/// bundles in one step → relaunch. Nothing changes on disk until every check has passed.
@MainActor
final class UpdateInstaller {
    enum Phase: Equatable {
        case downloading(received: Int64, expected: Int64)
        case verifying
        case installing
    }

    private let update: AvailableUpdate
    private let appURL: URL
    private let publicKey: String
    private let onPhase: (Phase) -> Void
    private var download: UpdateDownload?
    private var isCancelled = false

    init(update: AvailableUpdate, appURL: URL = Bundle.main.bundleURL, publicKey: String, onPhase: @escaping (Phase) -> Void) {
        self.update = update
        self.appURL = appURL
        self.publicKey = publicKey
        self.onPhase = onPhase
    }

    /// Problems that stop an install before anything is downloaded.
    static func preflightProblem(for update: AvailableUpdate, appURL: URL, publicKey: String?, isDevelopmentBuild: Bool) -> UpdateError? {
        if isDevelopmentBuild { return .developmentBuild }
        guard let publicKey, !publicKey.isEmpty, Data(base64Encoded: publicKey)?.count == 32 else { return .noUpdateKey }
        if let problem = UpdateInstallLocation.problem(for: appURL) { return problem }
        guard update.diskImage != nil else { return .missingDiskImage }
        guard update.signature != nil else { return .missingSignature }
        return nil
    }

    /// Installs the update and returns the work folder, which still holds the replaced app (the
    /// running process maps its files) for the relaunched app to delete. Throws
    /// `CancellationError` after `cancel()`.
    func install(bundleIdentifier: String) async throws -> URL {
        guard let diskImage = update.diskImage else { throw UpdateError.missingDiskImage }
        guard let signatureAsset = update.signature else { throw UpdateError.missingSignature }

        let workFolder: URL
        do {
            // On the app's volume, so the final swap is a rename.
            workFolder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
        var keepWorkFolder = false
        defer {
            if !keepWorkFolder { try? FileManager.default.removeItem(at: workFolder) }
        }

        onPhase(.downloading(received: 0, expected: diskImage.size))
        let signatureText = try await Self.fetchText(signatureAsset.downloadURL)
        try checkCancelled()

        let imageURL = workFolder.appendingPathComponent(diskImage.name)
        let download = UpdateDownload(url: diskImage.downloadURL, destination: imageURL) { [weak self] received, expected in
            Task { @MainActor in
                self?.onPhase(.downloading(received: received, expected: expected > 0 ? expected : diskImage.size))
            }
        }
        self.download = download
        try await download.run()
        self.download = nil
        try checkCancelled()

        onPhase(.verifying)
        let publicKey = self.publicKey
        let version = update.version
        let stagedApp = workFolder.appendingPathComponent("Hashlight.app")
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: imageURL, options: .mappedIfSafe)
            try UpdateVerification.verifyDiskImage(data, asset: diskImage, signatureText: signatureText, publicKeyBase64: publicKey)
            try Self.copyApp(fromDiskImage: imageURL, to: stagedApp, mountPoint: workFolder.appendingPathComponent("mount"))
            try UpdateVerification.verifyApp(at: stagedApp, bundleIdentifier: bundleIdentifier, version: version)
            Self.removeQuarantine(from: stagedApp)
        }.value
        try checkCancelled()

        onPhase(.installing)
        let appURL = self.appURL
        try await Task.detached(priority: .userInitiated) {
            try Self.exchange(stagedApp, with: appURL)
        }.value
        // The replaced app now sits in the work folder; the relaunched app deletes it.
        keepWorkFolder = true
        return workFolder
    }

    func cancel() {
        isCancelled = true
        download?.cancel()
    }

    private func checkCancelled() throws {
        if isCancelled { throw CancellationError() }
    }

    // MARK: - Steps

    private static func fetchText(_ url: URL) async throws -> String {
        let (data, response) = try await UpdateNetwork.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.httpStatus(http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func copyApp(fromDiskImage imageURL: URL, to stagedApp: URL, mountPoint: URL) throws {
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attach = run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-quiet", "-mountpoint", mountPoint.path, imageURL.path])
        guard attach.status == 0 else { throw UpdateError.mountFailed(attach.output.isEmpty ? "hdiutil failed" : attach.output) }
        defer {
            if run("/usr/bin/hdiutil", ["detach", "-quiet", mountPoint.path]).status != 0 {
                _ = run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mountPoint.path])
            }
        }
        let source = mountPoint.appendingPathComponent("Hashlight.app")
        guard FileManager.default.fileExists(atPath: source.path) else { throw UpdateError.appMissingFromDiskImage }
        let copy = run("/usr/bin/ditto", [source.path, stagedApp.path])
        guard copy.status == 0 else { throw UpdateError.installFailed(copy.output.isEmpty ? "the app could not be copied" : copy.output) }
    }

    /// Puts `staged` where `installed` is and `installed` where `staged` was, in one step
    /// (`RENAME_SWAP`). A file system without swaps gets two renames, undone if the second fails.
    nonisolated static func exchange(_ staged: URL, with installed: URL) throws {
        if renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0 { return }
        let swapError = errno
        guard swapError == ENOTSUP || swapError == EINVAL || swapError == EXDEV else {
            throw UpdateError.installFailed(String(cString: strerror(swapError)))
        }
        let aside = staged.deletingLastPathComponent().appendingPathComponent("Hashlight (replaced).app")
        do {
            try FileManager.default.moveItem(at: installed, to: aside)
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
        do {
            try FileManager.default.moveItem(at: staged, to: installed)
        } catch {
            try? FileManager.default.moveItem(at: aside, to: installed)
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }

    /// An app downloaded by Hashlight itself is not quarantined; this only matters if something
    /// else added the flag, which would make macOS block the verified update's first launch.
    nonisolated private static func removeQuarantine(from appURL: URL) {
        _ = run("/usr/bin/xattr", ["-d", "-r", "com.apple.quarantine", appURL.path])
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Starts a shell that waits for this process to exit (at most 30 s), then opens the app.
    static func relaunchAfterExit(appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "i=0; while /bin/kill -0 \"$1\" 2>/dev/null && [ $i -lt 300 ]; do /bin/sleep 0.1; i=$((i+1)); done; /usr/bin/open \"$2\"",
            "hashlight-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            appURL.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

/// The updater's HTTP requests: no cookies or cache, a Hashlight user agent, GitHub's API headers.
nonisolated enum UpdateNetwork {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: configuration)
    }()

    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "Hashlight/\(version) (macOS; +https://github.com/ib0ndar/Hashlight)"
    }

    static func data(from url: URL, accept: String? = nil) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        if url.host == "api.github.com" {
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw UpdateError.network(error.localizedDescription)
        }
    }
}

/// One file download with progress, through a delegate (the async URLSession API reports none).
nonisolated final class UpdateDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let url: URL
    private let destination: URL
    private let progress: @Sendable (Int64, Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var moveError: Error?

    init(url: URL, destination: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.url = url
        self.destination = destination
        self.progress = progress
    }

    func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": UpdateNetwork.userAgent]
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock {
                self.continuation = continuation
                let task = session.downloadTask(with: url)
                self.task = task
                task.resume()
            }
        }
    }

    func cancel() {
        lock.withLock { task }?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this returns.
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            lock.withLock { moveError = UpdateError.httpStatus(http.statusCode) }
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { moveError = UpdateError.installFailed(error.localizedDescription) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, moveError) = lock.withLock { () -> (CheckedContinuation<Void, Error>?, Error?) in
            defer { self.continuation = nil }
            return (self.continuation, self.moveError)
        }
        if let error = error as? URLError {
            continuation?.resume(throwing: error.code == .cancelled ? CancellationError() : UpdateError.network(error.localizedDescription))
        } else if let error {
            continuation?.resume(throwing: UpdateError.network(error.localizedDescription))
        } else if let moveError {
            continuation?.resume(throwing: moveError)
        } else {
            continuation?.resume()
        }
    }
}
