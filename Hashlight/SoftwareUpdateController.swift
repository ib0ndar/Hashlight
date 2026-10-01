import AppKit
import SwiftUI

/// How the updater talks to the user. The update window and alerts in the app; a recorder in tests.
@MainActor
protocol UpdatePresenting: AnyObject {
    /// Shows (or brings forward) the update window for `UpdateController.offeredUpdate`.
    func showOffer()
    func closeOffer()
    func showUpToDate(version: String)
    func showCheckFailure(_ message: String)
}

/// The in-app updater. Checks GitHub Releases when asked (Hashlight → Check for Updates…,
/// Settings → General → Check Now) and, while "Automatically check for updates" is on, once per
/// calendar day: at launch, and when the app stays open into a new day. Offers a newer release in
/// the update window and installs it (`UpdateInstaller`).
///
/// A manual check always reports: the update window, "up to date", or the error. An automatic
/// check is silent unless it finds a version the user has not skipped, and shows it only while
/// Hashlight is the active app. Only a successful check counts as the day's check.
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    static let defaultFeedURL = URL(string: "https://api.github.com/repos/ib0ndar/Hashlight/releases?per_page=20")!

    enum InstallState: Equatable {
        case idle
        case downloading(received: Int64, expected: Int64)
        case verifying
        case installing
        case failed(String, canOpenReleasePage: Bool)
    }

    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckDate: Date?
    /// The newer version the last check found this session, for the Settings status line.
    @Published private(set) var availableVersion: String?
    @Published private(set) var offeredUpdate: AvailableUpdate?
    @Published private(set) var installState: InstallState = .idle

    var presenter: UpdatePresenting?

    private let defaults: UserDefaults
    private let bundle: Bundle
    private let now: () -> Date
    private let fetchReleases: (URL) async throws -> [GitHubRelease]
    private let allowsAutomaticChecks: Bool
    private let isAutomaticCheckEnabled: () -> Bool
    private let isAppActive: () -> Bool
    private let isDevelopmentBuild: Bool

    private var reportsCurrentCheck = false
    private var lastFailedAutomaticAttempt: Date?
    private var offerWaitsForActivation = false
    private var installer: UpdateInstaller?
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        now: @escaping () -> Date = Date.init,
        fetchReleases: @escaping (URL) async throws -> [GitHubRelease] = UpdateController.fetchReleasesFromGitHub,
        allowsAutomaticChecks: Bool = UpdateController.automaticChecksAllowed,
        isAutomaticCheckEnabled: @escaping () -> Bool = { SettingsManager.shared.automaticallyChecksForUpdates },
        isAppActive: @escaping () -> Bool = { NSApplication.shared.isActive },
        isDevelopmentBuild: Bool = UpdateController.isDevelopmentBuild,
        presenter: UpdatePresenting? = nil
    ) {
        self.defaults = defaults
        self.bundle = bundle
        self.now = now
        self.fetchReleases = fetchReleases
        self.allowsAutomaticChecks = allowsAutomaticChecks
        self.isAutomaticCheckEnabled = isAutomaticCheckEnabled
        self.isAppActive = isAppActive
        self.isDevelopmentBuild = isDevelopmentBuild
        self.lastCheckDate = defaults.object(forKey: DefaultsKeys.lastUpdateCheck) as? Date
        self.presenter = presenter ?? UpdateWindowPresenter()
        (self.presenter as? UpdateWindowPresenter)?.controller = self
    }

    // MARK: - Build facts

    static var isDevelopmentBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Debug builds and test runs never check on their own (the test host shares the Debug
    /// settings domain); Check for Updates still works there.
    static var automaticChecksAllowed: Bool {
        !isDevelopmentBuild && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            && NSClassFromString("XCTestCase") == nil
    }

    var currentVersion: ReleaseVersion? { ReleaseVersion.ofBundle(bundle) }

    var feedURL: URL {
        (bundle.infoDictionary?["HashlightUpdateFeedURL"] as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) } ?? Self.defaultFeedURL
    }

    var publicKey: String? {
        bundle.infoDictionary?["HashlightUpdatePublicKey"] as? String
    }

    var skippedVersion: ReleaseVersion? {
        defaults.string(forKey: DefaultsKeys.skippedUpdateVersion).flatMap(ReleaseVersion.init)
    }

    // MARK: - Scheduling

    /// Called once at launch: the first automatic check a few seconds later, then again whenever
    /// the day changes, the Mac wakes, or the app becomes active (each only checks if due).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        guard allowsAutomaticChecks else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.checkAutomaticallyIfDue() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showWaitingOffer()
                _ = self?.checkAutomaticallyIfDue()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.checkAutomaticallyIfDue() }
        })
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.checkAutomaticallyIfDue()
        }
    }

    /// Runs an automatic check if they are on and none has succeeded today. Returns whether a
    /// check started.
    @discardableResult
    func checkAutomaticallyIfDue() -> Bool {
        guard allowsAutomaticChecks, isAutomaticCheckEnabled(), !isChecking, !isInstalling else { return false }
        let date = now()
        guard UpdateSchedule.isAutomaticCheckDue(lastCheck: lastCheckDate, now: date),
              UpdateSchedule.mayRetry(after: lastFailedAutomaticAttempt, now: date) else { return false }
        automaticCheck = Task { await check(userInitiated: false) }
        return true
    }

    /// The automatic check started last (tests wait for it).
    private(set) var automaticCheck: Task<Void, Never>?

    /// Hashlight → Check for Updates… and Settings → Check Now.
    func checkForUpdates() {
        if isInstalling {
            presenter?.showOffer()
            return
        }
        Task { await check(userInitiated: true) }
    }

    func check(userInitiated: Bool) async {
        if userInitiated { reportsCurrentCheck = true }
        guard !isChecking else { return }
        isChecking = true
        reportsCurrentCheck = userInitiated
        defer {
            isChecking = false
            reportsCurrentCheck = false
        }

        guard let current = currentVersion else {
            if reportsCurrentCheck { presenter?.showCheckFailure(UpdateError.unknownCurrentVersion.localizedDescription) }
            return
        }
        let releases: [GitHubRelease]
        do {
            releases = try await fetchReleases(feedURL)
        } catch {
            if reportsCurrentCheck {
                presenter?.showCheckFailure(error.localizedDescription)
            } else {
                lastFailedAutomaticAttempt = now()
            }
            return
        }

        let date = now()
        lastCheckDate = date
        defaults.set(date, forKey: DefaultsKeys.lastUpdateCheck)
        lastFailedAutomaticAttempt = nil

        guard let update = UpdateFeed.availableUpdate(in: releases, current: current) else {
            availableVersion = nil
            if reportsCurrentCheck { presenter?.showUpToDate(version: current.text) }
            return
        }
        availableVersion = update.version.text
        if reportsCurrentCheck {
            offer(update, waitForActivation: false)
        } else if UpdateSchedule.offersAutomatically(update.version, skipped: skippedVersion) {
            offer(update, waitForActivation: true)
        }
    }

    private func offer(_ update: AvailableUpdate, waitForActivation: Bool) {
        if isInstalling {
            presenter?.showOffer()
            return
        }
        if isFailed { installState = .idle }
        offeredUpdate = update
        if waitForActivation && !isAppActive() {
            offerWaitsForActivation = true
        } else {
            offerWaitsForActivation = false
            presenter?.showOffer()
        }
    }

    private func showWaitingOffer() {
        guard offerWaitsForActivation, offeredUpdate != nil else { return }
        offerWaitsForActivation = false
        presenter?.showOffer()
    }

    // MARK: - Update window actions

    /// Automatic checks no longer offer this version; a newer one is offered again.
    func skipOfferedVersion() {
        if let version = offeredUpdate?.version {
            defaults.set(version.text, forKey: DefaultsKeys.skippedUpdateVersion)
        }
        closeOffer()
    }

    /// Today's check already happened, so the next automatic check (tomorrow) offers it again.
    func remindLater() {
        closeOffer()
    }

    func openReleasePage() {
        if let url = offeredUpdate?.release.pageURL {
            NSWorkspace.shared.open(url)
        }
    }

    func dismissInstallFailure() {
        if case .failed = installState { installState = .idle }
    }

    /// The window can close unless the update is being verified or installed.
    var canCloseOffer: Bool {
        switch installState {
        case .verifying, .installing: return false
        default: return true
        }
    }

    /// The window closed (its close button, Skip, or Remind Me Tomorrow).
    func offerWindowDidClose() {
        installer?.cancel()
        offeredUpdate = nil
        offerWaitsForActivation = false
        if case .failed = installState { installState = .idle }
    }

    private func closeOffer() {
        presenter?.closeOffer()
        offerWindowDidClose()
    }

    func cancelInstall() {
        installer?.cancel()
    }

    func installOfferedUpdate() {
        guard let update = offeredUpdate, !isInstalling else { return }
        if let problem = UpdateInstaller.preflightProblem(for: update, appURL: bundle.bundleURL, publicKey: publicKey, isDevelopmentBuild: isDevelopmentBuild) {
            installState = .failed(problem.localizedDescription, canOpenReleasePage: true)
            return
        }
        guard let publicKey, let bundleIdentifier = bundle.bundleIdentifier else { return }
        let installer = UpdateInstaller(update: update, appURL: bundle.bundleURL, publicKey: publicKey) { [weak self] phase in
            guard let self, self.installer != nil else { return }
            switch phase {
            case .downloading(let received, let expected):
                // Progress reports can arrive after verification has started.
                if case .downloading = self.installState {
                    self.installState = .downloading(received: received, expected: expected)
                }
            case .verifying: self.installState = .verifying
            case .installing: self.installState = .installing
            }
        }
        self.installer = installer
        installState = .downloading(received: 0, expected: update.diskImage?.size ?? 0)
        Task {
            do {
                let workFolder = try await installer.install(bundleIdentifier: bundleIdentifier)
                self.installer = nil
                relaunch(cleaningUp: workFolder)
            } catch is CancellationError {
                self.installer = nil
                installState = .idle
            } catch {
                self.installer = nil
                installState = .failed(error.localizedDescription, canOpenReleasePage: true)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = installState { return true }
        return false
    }

    /// Downloading, verifying, or installing.
    var isInstalling: Bool {
        installState != .idle && !isFailed
    }

    /// Saves the open documents for the new version, starts the relaunch, and quits.
    private func relaunch(cleaningUp workFolder: URL) {
        let documents = DocumentManager.shared
        UpdateRelaunchState(
            documentPaths: documents.openDocuments.map(\.url.path),
            selectedPath: documents.selectedDocument?.url.path,
            cleanupPath: workFolder.path,
            savedAt: now()
        ).save(to: defaults)
        do {
            try UpdateInstaller.relaunchAfterExit(appURL: bundle.bundleURL)
        } catch {
            installState = .failed("The update was installed, but Hashlight could not reopen itself. Quit Hashlight and open it again.", canOpenReleasePage: false)
            return
        }
        NSApplication.shared.terminate(nil)
    }

    /// After an update relaunched the app: reopens the documents that were open, selects the one
    /// that was selected, and deletes the downloaded image and the replaced app.
    func restoreAfterUpdate(documentManager: DocumentManager = .shared) {
        guard let state = UpdateRelaunchState.take(from: defaults, now: now()) else { return }
        if let cleanupPath = state.cleanupPath, cleanupPath.contains("/TemporaryItems/") {
            Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(atPath: cleanupPath)
            }
        }
        for path in state.documentPaths where FileManager.default.fileExists(atPath: path) {
            documentManager.loadDocument(from: URL(fileURLWithPath: path))
        }
        if let selectedPath = state.selectedPath {
            let selected = URL(fileURLWithPath: selectedPath).standardizedFileURL.path
            if let document = documentManager.openDocuments.first(where: { $0.url.standardizedFileURL.path == selected }) {
                documentManager.selectedDocumentId = document.id
            }
        }
    }

    // MARK: - Settings status

    private static let checkDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.formattingContext = .middleOfSentence
        return formatter
    }()

    /// "Last checked today at 09:14." for Settings → General → Updates.
    var statusText: String {
        if isChecking { return "Checking for updates…" }
        guard let lastCheckDate else { return "Not checked yet." }
        let checked = "Last checked \(Self.checkDateFormatter.string(from: lastCheckDate))."
        if let availableVersion { return "\(checked) Hashlight \(availableVersion) is available." }
        return checked
    }

    // MARK: - GitHub

    nonisolated static func fetchReleasesFromGitHub(_ url: URL) async throws -> [GitHubRelease] {
        let (data, response) = try await UpdateNetwork.data(from: url, accept: "application/vnd.github+json")
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 || (http.statusCode == 403 && http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0") {
                throw UpdateError.rateLimited
            }
            guard (200..<300).contains(http.statusCode) else { throw UpdateError.httpStatus(http.statusCode) }
        }
        do {
            return try GitHubRelease.decodeList(from: data)
        } catch {
            throw UpdateError.unreadableFeed
        }
    }
}

// MARK: - Window and alerts

@MainActor
final class UpdateWindowPresenter: NSObject, UpdatePresenting, NSWindowDelegate {
    weak var controller: UpdateController?
    private var window: NSWindow?

    func showOffer() {
        guard let controller else { return }
        if window == nil {
            let hosting = NSHostingController(rootView: UpdateOfferView(controller: controller))
            hosting.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Software Update"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.identifier = NSUserInterfaceItemIdentifier("softwareUpdate")
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: UpdateOfferView.idealWidth, height: UpdateOfferView.idealHeight))
            window.center()
            self.window = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // SwiftUI would focus the first control, the View on GitHub link, and ring it. Return
        // and Escape still reach Update Now and Remind Me Tomorrow; Tab still moves focus.
        DispatchQueue.main.async { [weak window] in
            window?.makeFirstResponder(nil)
        }
    }

    func closeOffer() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        controller?.canCloseOffer ?? true
    }

    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }
        window = nil
        controller?.offerWindowDidClose()
    }

    func showUpToDate(version: String) {
        showAlert(title: "Hashlight is up to date", message: "Hashlight \(version) is the newest version available.", style: .informational)
    }

    func showCheckFailure(_ message: String) {
        showAlert(title: "Hashlight couldn't check for updates", message: message, style: .warning)
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

/// The update window: what is new, the release notes of every missed version (rendered like a
/// document, in the reader's theme and font), and Skip This Version / Remind Me Tomorrow /
/// Update Now; while installing, the progress or what went wrong.
struct UpdateOfferView: View {
    static let idealWidth: CGFloat = 640
    static let idealHeight: CGFloat = 540

    @ObservedObject var controller: UpdateController
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var dockIcon = DockIconController.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var notesDocumentID = UUID()
    @State private var notesHeading: String?

    var body: some View {
        Group {
            if let update = controller.offeredUpdate {
                content(update)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 500, idealWidth: Self.idealWidth, minHeight: 400, idealHeight: Self.idealHeight)
    }

    private func content(_ update: AvailableUpdate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: dockIcon.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("A new version of Hashlight is available")
                        .font(.title3.weight(.semibold))
                    Text("Hashlight \(update.version.text) is available — you have \(controller.currentVersion?.text ?? "an older version"). Would you like to update now?")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(update.newerReleases.count > 1 ? "Release notes of the \(update.newerReleases.count) new versions:" : "Release notes:")
                    .font(.headline)
                Spacer()
                Link("View on GitHub", destination: update.release.pageURL)
            }

            MarkdownTextView(
                content: update.releaseNotes,
                baseURL: nil,
                documentId: notesDocumentID,
                scrollToHeadingId: $notesHeading,
                searchText: "",
                currentMatchIndex: 0,
                mainFontID: settings.mainPreviewFontID,
                fixedFontID: settings.fixedPreviewFontID,
                mainFontSize: 13,
                fixedFontSize: 11,
                theme: PreviewThemeCatalog.resolve(
                    lightID: settings.lightPreviewThemeID,
                    darkID: settings.darkPreviewThemeID,
                    colorScheme: colorScheme
                ),
                contentWidth: .full,
                pageMargin: .compact,
                showsFrontmatter: false,
                verticalInset: 12
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            .frame(minHeight: 160)

            footer
        }
        .padding(20)
    }

    @ViewBuilder private var footer: some View {
        switch controller.installState {
        case .idle:
            HStack {
                Button("Skip This Version") { controller.skipOfferedVersion() }
                Spacer()
                Button("Remind Me Tomorrow") { controller.remindLater() }
                    .keyboardShortcut(.cancelAction)
                Button("Update Now") { controller.installOfferedUpdate() }
                    .keyboardShortcut(.defaultAction)
            }
        case .downloading(let received, let expected):
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: expected > 0 ? min(1, Double(received) / Double(expected)) : 0)
                    Text("Downloading… \(Self.bytes(received)) of \(Self.bytes(expected))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button("Cancel") { controller.cancelInstall() }
                    .keyboardShortcut(.cancelAction)
            }
        case .verifying:
            progressRow("Verifying the update…")
        case .installing:
            progressRow("Installing… Hashlight reopens in a moment.")
        case .failed(let message, let canOpenReleasePage):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if canOpenReleasePage {
                    Button("Open Release Page") { controller.openReleasePage() }
                }
                Button("OK") { controller.dismissInstallFailure() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
