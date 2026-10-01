import CryptoKit
import Foundation
import Security

// The parts of the in-app updater that do not touch the UI: release versions, reading GitHub's
// releases, the release-notes excerpt, the daily schedule, and verifying a downloaded update.

/// A release version: the numbers of a `vX.Y.Z` tag or a bundle's short version string.
/// Trailing zeros do not count, so 1.2 and 1.2.0 are the same version.
nonisolated struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// The version as written, without a leading "v" ("1.2.0" for the tag "v1.2.0").
    let text: String
    private let numbers: [Int]

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        self.text = text
        self.numbers = numbers
    }

    var description: String { text }

    static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool { lhs.numbers == rhs.numbers }

    func hash(into hasher: inout Hasher) { hasher.combine(numbers) }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    /// The running app's version.
    static func ofBundle(_ bundle: Bundle) -> ReleaseVersion? {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(ReleaseVersion.init)
    }
}

/// One entry of GitHub's "list releases" response.
nonisolated struct GitHubRelease: Decodable, Equatable, Sendable {
    nonisolated struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let size: Int64
        /// "sha256:<hex>", computed by GitHub when the asset was uploaded.
        let digest: String?
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case downloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let pageURL: URL
    let isDraft: Bool
    let isPrerelease: Bool
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, body, assets
        case tagName = "tag_name"
        case pageURL = "html_url"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
        case publishedAt = "published_at"
    }

    var version: ReleaseVersion? { ReleaseVersion(tagName) }

    /// "Hashlight 1.2" as the release is titled, or one made from the tag.
    var title: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return "Hashlight \(version?.text ?? tagName)"
    }

    static func decodeList(from data: Data) throws -> [GitHubRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitHubRelease].self, from: data)
    }
}

/// A newer release than the running app, with everything the update window shows.
nonisolated struct AvailableUpdate: Equatable, Sendable {
    /// The newest release; the one Update Now installs.
    let release: GitHubRelease
    let version: ReleaseVersion
    /// Every published release newer than the running app, newest first (includes `release`).
    let newerReleases: [GitHubRelease]

    /// The release's disk image: `Hashlight-<version>.dmg`.
    var diskImage: GitHubRelease.Asset? {
        release.assets.first { $0.name == "Hashlight-\(version.text).dmg" }
    }

    /// The disk image's Ed25519 signature: `Hashlight-<version>.dmg.sig`.
    var signature: GitHubRelease.Asset? {
        guard let diskImage else { return nil }
        return release.assets.first { $0.name == diskImage.name + ".sig" }
    }

    /// The notes of every missed release, newest first, each cut before its install section.
    var releaseNotes: String {
        if newerReleases.count == 1 {
            return ReleaseNotes.excerpt(from: release.body)
        }
        return newerReleases
            .map { "# \($0.title)\n\n\(ReleaseNotes.excerpt(from: $0.body))" }
            .joined(separator: "\n\n")
    }
}

nonisolated enum UpdateFeed {
    /// The newest published release (not a draft or pre-release) newer than `current`, or nil.
    static func availableUpdate(in releases: [GitHubRelease], current: ReleaseVersion) -> AvailableUpdate? {
        var seen = Set<ReleaseVersion>()
        let newer = releases
            .filter { !$0.isDraft && !$0.isPrerelease }
            .compactMap { release in release.version.map { (release, $0) } }
            .filter { $0.1 > current }
            .sorted { $0.1 > $1.1 }
            .filter { seen.insert($0.1).inserted }
        guard let newest = newer.first else { return nil }
        return AvailableUpdate(release: newest.0, version: newest.1, newerReleases: newer.map(\.0))
    }
}

nonisolated enum ReleaseNotes {
    /// An HTML comment that ends the part of a release's notes the update window shows. Without
    /// it, the notes end before a heading that starts with "Install".
    static let endMarker = "<!-- end of update notes -->"

    static func excerpt(from body: String?) -> String {
        let lines = (body ?? "").replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var kept: [String] = []
        var fence: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
            } else if trimmed.lowercased() == endMarker || isInstallHeading(trimmed) {
                break
            }
            kept.append(line)
        }
        while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty || last.trimmingCharacters(in: .whitespaces) == "---" {
            kept.removeLast()
        }
        let excerpt = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return excerpt.isEmpty ? "_No release notes were published for this version._" : excerpt
    }

    private static func isInstallHeading(_ line: String) -> Bool {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return false }
        let title = line.dropFirst(hashes)
        guard title.first == " " else { return false }
        return title.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("install")
    }
}

nonisolated enum UpdateSchedule {
    /// A failed automatic check is retried at the next opportunity after this long.
    static let retryInterval: TimeInterval = 60 * 60

    /// Automatic checks run once per calendar day: due when the last successful check was on
    /// another day (or never happened).
    static func isAutomaticCheckDue(lastCheck: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastCheck else { return true }
        return !calendar.isDate(lastCheck, inSameDayAs: now)
    }

    static func mayRetry(after failedAttempt: Date?, now: Date) -> Bool {
        guard let failedAttempt else { return true }
        return now.timeIntervalSince(failedAttempt) >= retryInterval || now < failedAttempt
    }

    /// An automatic check offers a version unless the user skipped it (or a newer one).
    static func offersAutomatically(_ version: ReleaseVersion, skipped: ReleaseVersion?) -> Bool {
        guard let skipped else { return true }
        return version > skipped
    }
}

/// What can stop an update. The descriptions are shown to the user.
nonisolated enum UpdateError: Error, Equatable, Sendable, LocalizedError {
    case network(String)
    case rateLimited
    case httpStatus(Int)
    case unreadableFeed
    case unknownCurrentVersion
    case developmentBuild
    case noUpdateKey
    case missingDiskImage
    case missingSignature
    case downloadIncomplete
    case checksumMismatch
    case signatureInvalid
    case mountFailed(String)
    case appMissingFromDiskImage
    case wrongApp(String?)
    case wrongVersion(found: String?, expected: String)
    case needsNewerMacOS(String)
    case codeSignatureInvalid
    case translocated
    case readOnlyLocation
    case locationNotWritable
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return "Hashlight couldn't reach GitHub: \(message)"
        case .rateLimited:
            return "GitHub is limiting requests from this network for now. Try again in an hour."
        case .httpStatus(let status):
            return "GitHub answered with an error (HTTP \(status))."
        case .unreadableFeed:
            return "GitHub's answer could not be read."
        case .unknownCurrentVersion:
            return "This copy of Hashlight has no version number."
        case .developmentBuild:
            return "Development builds can't install updates. Download the update from the release page instead."
        case .noUpdateKey:
            return "This copy of Hashlight has no key to verify updates. Download the update from the release page instead."
        case .missingDiskImage:
            return "The release has no disk image to install."
        case .missingSignature:
            return "The release's disk image is not signed, so it can't be verified."
        case .downloadIncomplete:
            return "The download is incomplete."
        case .checksumMismatch:
            return "The downloaded disk image does not match the checksum GitHub published for it."
        case .signatureInvalid:
            return "The downloaded disk image's signature is not valid. It was not installed."
        case .mountFailed(let message):
            return "The disk image could not be opened: \(message)"
        case .appMissingFromDiskImage:
            return "The disk image does not contain Hashlight."
        case .wrongApp(let identifier):
            return "The disk image contains a different app (\(identifier ?? "unknown"))."
        case .wrongVersion(let found, let expected):
            return "The disk image contains version \(found ?? "unknown"), not \(expected)."
        case .needsNewerMacOS(let version):
            return "This update needs macOS \(version) or later."
        case .codeSignatureInvalid:
            return "The app in the disk image is damaged (its code signature is not valid)."
        case .translocated:
            return "macOS is running Hashlight from a temporary location. Move Hashlight to the Applications folder, open it from there, and try again."
        case .readOnlyLocation:
            return "Hashlight is running from a read-only disk, such as its disk image. Move Hashlight to the Applications folder, open it from there, and try again."
        case .locationNotWritable:
            return "Hashlight can't replace itself in its current folder (you may not have permission to change it)."
        case .installFailed(let message):
            return "The update could not be installed: \(message)"
        }
    }
}

nonisolated enum UpdateVerification {
    /// The hex SHA-256 in an asset digest ("sha256:<hex>"), or nil for another or no digest.
    static func sha256(fromDigest digest: String?) -> String? {
        guard let digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        return hex.count == 64 && hex.allSatisfy(\.isHexDigit) ? String(hex) : nil
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `signatureText` (base64, as in a `.sig` asset) is an Ed25519 signature of `data`
    /// by the key `publicKeyBase64`.
    static func isValidSignature(_ signatureText: String, of data: Data, publicKeyBase64: String) -> Bool {
        let trimmed = signatureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: trimmed),
              let rawKey = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey) else { return false }
        return publicKey.isValidSignature(signature, for: data)
    }

    /// Checks a downloaded disk image: size, GitHub's checksum when there is one, signature.
    static func verifyDiskImage(_ data: Data, asset: GitHubRelease.Asset, signatureText: String, publicKeyBase64: String) throws {
        guard Int64(data.count) == asset.size else { throw UpdateError.downloadIncomplete }
        if let expected = sha256(fromDigest: asset.digest), sha256Hex(of: data) != expected {
            throw UpdateError.checksumMismatch
        }
        guard isValidSignature(signatureText, of: data, publicKeyBase64: publicKeyBase64) else {
            throw UpdateError.signatureInvalid
        }
    }

    /// Checks the app copied out of the disk image before it replaces the running one.
    static func verifyApp(
        at appURL: URL,
        bundleIdentifier: String,
        version: ReleaseVersion,
        operatingSystem: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        checkCodeSignature: Bool = true
    ) throws {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            throw UpdateError.appMissingFromDiskImage
        }
        let identifier = info["CFBundleIdentifier"] as? String
        guard identifier == bundleIdentifier else { throw UpdateError.wrongApp(identifier) }
        let found = info["CFBundleShortVersionString"] as? String
        guard found.flatMap(ReleaseVersion.init) == version else {
            throw UpdateError.wrongVersion(found: found, expected: version.text)
        }
        if let minimum = info["LSMinimumSystemVersion"] as? String, !isSatisfied(minimum, by: operatingSystem) {
            throw UpdateError.needsNewerMacOS(minimum)
        }
        if checkCodeSignature, !hasValidCodeSignature(appURL) {
            throw UpdateError.codeSignatureInvalid
        }
    }

    static func isSatisfied(_ minimum: String, by system: OperatingSystemVersion) -> Bool {
        let parts = minimum.split(separator: ".").map { Int($0) ?? 0 }
        let required = [parts.first ?? 0, parts.count > 1 ? parts[1] : 0, parts.count > 2 ? parts[2] : 0]
        let actual = [system.majorVersion, system.minorVersion, system.patchVersion]
        return !actual.lexicographicallyPrecedes(required)
    }

    /// The bundle's code signature is intact, nested code included. Hashlight is ad-hoc signed,
    /// so this proves integrity, not who signed it; the disk image's Ed25519 signature does that.
    static func hasValidCodeSignature(_ appURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidityWithErrors(staticCode, flags, nil, nil) == errSecSuccess
    }
}

nonisolated enum UpdateInstallLocation {
    /// Why the app at `appURL` cannot be replaced in place, or nil if it can.
    static func problem(for appURL: URL, fileManager: FileManager = .default) -> UpdateError? {
        if appURL.path.contains("/AppTranslocation/") { return .translocated }
        if (try? appURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            return .readOnlyLocation
        }
        let folder = appURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: folder.path),
              fileManager.isWritableFile(atPath: appURL.path) else { return .locationNotWritable }
        return nil
    }
}

/// What the relaunched app restores after an update: the open documents and the selected one.
/// Written by the version that installs an update and read by the version it installed, so the
/// format must stay readable by later versions.
nonisolated struct UpdateRelaunchState: Codable, Equatable, Sendable {
    static let defaultsKey = "updateRelaunchState"
    /// A saved state older than this is ignored (the relaunch did not happen).
    static let maximumAge: TimeInterval = 10 * 60

    var documentPaths: [String]
    var selectedPath: String?
    /// The temporary folder that held the download and the replaced app.
    var cleanupPath: String?
    var savedAt: Date

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// The saved state, removed from `defaults`; nil if there is none or it is stale.
    static func take(from defaults: UserDefaults, now: Date = Date()) -> UpdateRelaunchState? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        defaults.removeObject(forKey: defaultsKey)
        guard let state = try? JSONDecoder().decode(UpdateRelaunchState.self, from: data),
              abs(now.timeIntervalSince(state.savedAt)) <= maximumAge else { return nil }
        return state
    }
}
