import CryptoKit
import XCTest
@testable import Hashlight

// MARK: - Fixtures

private nonisolated enum UpdateFixtures {
    static let releasesJSON = """
    [
      {"tag_name": "v2.0.0", "name": "Draft", "body": "Not yet.", "html_url": "https://github.com/ib0ndar/Hashlight/releases/tag/untagged", "draft": true, "prerelease": false, "published_at": null, "assets": []},
      {"tag_name": "v1.5.0", "name": "Hashlight 1.5 beta", "body": "Beta.", "html_url": "https://github.com/ib0ndar/Hashlight/releases/tag/v1.5.0", "draft": false, "prerelease": true, "published_at": "2026-11-05T10:00:00Z", "assets": []},
      {"tag_name": "nightly", "name": "Nightly", "body": "", "html_url": "https://github.com/ib0ndar/Hashlight/releases/tag/nightly", "draft": false, "prerelease": false, "published_at": "2026-11-04T10:00:00Z", "assets": []},
      {"tag_name": "v1.3.0", "name": "Hashlight 1.3", "body": "Hashlight 1.3 adds things.\\n\\n## What's new\\n\\n- One\\n\\n## Install\\n\\nDrag it to Applications.", "html_url": "https://github.com/ib0ndar/Hashlight/releases/tag/v1.3.0", "draft": false, "prerelease": false, "published_at": "2026-11-01T10:00:00Z",
       "assets": [
         {"name": "Hashlight-1.3.0.dmg", "size": 7104715, "digest": "sha256:bf43696d4b5ac70abf0d57cddbd2994d24b9a629f8c56183fb0aa1142bd8a542", "browser_download_url": "https://github.com/ib0ndar/Hashlight/releases/download/v1.3.0/Hashlight-1.3.0.dmg"},
         {"name": "Hashlight-1.3.0.dmg.sig", "size": 89, "digest": null, "browser_download_url": "https://github.com/ib0ndar/Hashlight/releases/download/v1.3.0/Hashlight-1.3.0.dmg.sig"}
       ]},
      {"tag_name": "v1.2.1", "name": "", "body": "Fixes.", "html_url": "https://github.com/ib0ndar/Hashlight/releases/tag/v1.2.1", "draft": false, "prerelease": false, "published_at": "2026-10-20T10:00:00Z", "assets": []},
      {"tag_name": "v1.2.0", "name": "Hashlight 1.2", "body": "Updates.", "html_url": "https://github.com/ib0ndar/Hashlight/releases/tag/v1.2.0", "draft": false, "prerelease": false, "published_at": "2026-10-02T10:00:00Z", "assets": []},
      {"tag_name": "v1.1.0", "name": "Hashlight 1.1", "body": null, "html_url": "https://github.com/ib0ndar/Hashlight/releases/tag/v1.1.0", "draft": false, "prerelease": false, "published_at": "2026-10-01T18:21:02Z", "assets": []}
    ]
    """

    static func releases() throws -> [GitHubRelease] {
        try GitHubRelease.decodeList(from: Data(releasesJSON.utf8))
    }

    static func release(_ tag: String, body: String? = "Notes.", assets: [GitHubRelease.Asset] = []) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            name: nil,
            body: body,
            pageURL: URL(string: "https://github.com/ib0ndar/Hashlight/releases/tag/\(tag)")!,
            isDraft: false,
            isPrerelease: false,
            publishedAt: nil,
            assets: assets
        )
    }

    static func asset(_ name: String, size: Int64 = 10, digest: String? = nil) -> GitHubRelease.Asset {
        GitHubRelease.Asset(name: name, size: size, digest: digest, downloadURL: URL(string: "https://example.invalid/\(name)")!)
    }

    /// A minimal app bundle (an Info.plist only) in a fresh temporary folder.
    static func makeApp(identifier: String = "io.github.ib0ndar.hashlight", version: String = "1.2.0", minimumSystem: String? = "13.0") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-update-tests-\(UUID().uuidString)")
        let app = folder.appendingPathComponent("Hashlight.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        var info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleShortVersionString": version,
            "CFBundlePackageType": "APPL",
            "HashlightUpdatePublicKey": Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString(),
        ]
        if let minimumSystem { info["LSMinimumSystemVersion"] = minimumSystem }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }
}

// MARK: - Versions

nonisolated final class ReleaseVersionTests: XCTestCase {
    func testTagsAndShortVersionsParse() throws {
        XCTAssertEqual(try XCTUnwrap(ReleaseVersion("v1.2.0")).text, "1.2.0")
        XCTAssertEqual(try XCTUnwrap(ReleaseVersion("1.2")).text, "1.2")
        XCTAssertEqual(ReleaseVersion("v1.2.0"), ReleaseVersion("1.2"))
        for invalid in ["", "v", "1..2", "1.2.x", "1.2.0-beta", "nightly", "1.2.3.4.5", "-1.0"] {
            XCTAssertNil(ReleaseVersion(invalid), invalid)
        }
    }

    func testVersionsCompareNumerically() throws {
        func version(_ text: String) throws -> ReleaseVersion { try XCTUnwrap(ReleaseVersion(text)) }
        XCTAssertLessThan(try version("1.9.0"), try version("1.10.0"))
        XCTAssertLessThan(try version("1.2"), try version("1.2.1"))
        XCTAssertLessThan(try version("1.2.9"), try version("2"))
        XCTAssertFalse(try version("1.2.0") < version("1.2"))
        XCTAssertEqual(Set([try version("1.2"), try version("1.2.0")]).count, 1)
    }
}

// MARK: - Feed and notes

nonisolated final class UpdateFeedTests: XCTestCase {
    func testGitHubsReleaseListDecodes() throws {
        let releases = try UpdateFixtures.releases()
        XCTAssertEqual(releases.count, 7)
        let release = releases[3]
        XCTAssertEqual(release.tagName, "v1.3.0")
        XCTAssertEqual(release.title, "Hashlight 1.3")
        XCTAssertEqual(release.assets.first?.size, 7_104_715)
        XCTAssertNotNil(release.publishedAt)
        XCTAssertEqual(releases[4].title, "Hashlight 1.2.1", "an empty name falls back to the tag")
        XCTAssertNil(releases[0].publishedAt)
    }

    func testTheNewestPublishedReleaseIsOfferedWithEveryMissedOne() throws {
        let update = try XCTUnwrap(UpdateFeed.availableUpdate(in: try UpdateFixtures.releases(), current: try XCTUnwrap(ReleaseVersion("1.2.0"))))
        XCTAssertEqual(update.version.text, "1.3.0", "drafts, pre-releases, and other tags are ignored")
        XCTAssertEqual(update.newerReleases.map(\.tagName), ["v1.3.0", "v1.2.1"])
        XCTAssertEqual(update.diskImage?.name, "Hashlight-1.3.0.dmg")
        XCTAssertEqual(update.signature?.name, "Hashlight-1.3.0.dmg.sig")
    }

    func testNoUpdateWhenTheAppIsCurrentOrNewer() throws {
        let releases = try UpdateFixtures.releases()
        XCTAssertNil(UpdateFeed.availableUpdate(in: releases, current: try XCTUnwrap(ReleaseVersion("1.3.0"))))
        XCTAssertNil(UpdateFeed.availableUpdate(in: releases, current: try XCTUnwrap(ReleaseVersion("1.4"))))
        XCTAssertNil(UpdateFeed.availableUpdate(in: [], current: try XCTUnwrap(ReleaseVersion("1.0"))))
    }

    func testAssetsMustCarryTheReleaseVersion() throws {
        let update = try XCTUnwrap(UpdateFeed.availableUpdate(
            in: [UpdateFixtures.release("v1.3.0", assets: [UpdateFixtures.asset("Hashlight-1.2.0.dmg"), UpdateFixtures.asset("Hashlight-1.3.0.dmg")])],
            current: try XCTUnwrap(ReleaseVersion("1.2.0"))
        ))
        XCTAssertEqual(update.diskImage?.name, "Hashlight-1.3.0.dmg")
        XCTAssertNil(update.signature, "a disk image without its .sig asset cannot be installed")
    }

    func testNotesStopAtTheInstallSectionOrTheMarker() {
        XCTAssertEqual(
            ReleaseNotes.excerpt(from: "Intro.\n\n## What's new\n\n- One\n\n## Install\n\n1. Drag it.\n\n## Credits\n\nPeople."),
            "Intro.\n\n## What's new\n\n- One"
        )
        XCTAssertEqual(
            ReleaseNotes.excerpt(from: "Intro.\r\n\r\n---\r\n\r\n<!-- end of update notes -->\r\n\r\nChecksum"),
            "Intro."
        )
        XCTAssertEqual(
            ReleaseNotes.excerpt(from: "Run:\n\n```\n## Install\n```\n\n### Installing notes\n\nHidden."),
            "Run:\n\n```\n## Install\n```",
            "a heading inside a code block does not end the notes"
        )
        XCTAssertEqual(ReleaseNotes.excerpt(from: "##Install is not a heading\n\nKept."), "##Install is not a heading\n\nKept.")
        XCTAssertEqual(ReleaseNotes.excerpt(from: nil), "_No release notes were published for this version._")
        XCTAssertEqual(ReleaseNotes.excerpt(from: "## Install\n\nOnly install steps."), "_No release notes were published for this version._")
    }

    func testOneMissedReleaseShowsItsNotesAndSeveralGetTitles() throws {
        let releases = try UpdateFixtures.releases()
        let one = try XCTUnwrap(UpdateFeed.availableUpdate(in: releases, current: try XCTUnwrap(ReleaseVersion("1.2.1"))))
        XCTAssertEqual(one.releaseNotes, "Hashlight 1.3 adds things.\n\n## What's new\n\n- One")

        let two = try XCTUnwrap(UpdateFeed.availableUpdate(in: releases, current: try XCTUnwrap(ReleaseVersion("1.2.0"))))
        XCTAssertEqual(two.releaseNotes, "# Hashlight 1.3\n\nHashlight 1.3 adds things.\n\n## What's new\n\n- One\n\n# Hashlight 1.2.1\n\nFixes.")
    }
}

// MARK: - Schedule

nonisolated final class UpdateScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        return formatter.date(from: text)!
    }

    func testAutomaticChecksRunOncePerCalendarDay() {
        XCTAssertTrue(UpdateSchedule.isAutomaticCheckDue(lastCheck: nil, now: date("2026-10-02T09:00:00+02:00"), calendar: calendar))
        XCTAssertFalse(UpdateSchedule.isAutomaticCheckDue(lastCheck: date("2026-10-02T00:05:00+02:00"), now: date("2026-10-02T23:55:00+02:00"), calendar: calendar))
        XCTAssertTrue(UpdateSchedule.isAutomaticCheckDue(lastCheck: date("2026-10-01T23:55:00+02:00"), now: date("2026-10-02T00:05:00+02:00"), calendar: calendar), "a new calendar day, not 24 hours")
    }

    func testAFailedCheckIsRetriedAfterAnHour() {
        let failed = date("2026-10-02T09:00:00+02:00")
        XCTAssertTrue(UpdateSchedule.mayRetry(after: nil, now: failed))
        XCTAssertFalse(UpdateSchedule.mayRetry(after: failed, now: failed.addingTimeInterval(59 * 60)))
        XCTAssertTrue(UpdateSchedule.mayRetry(after: failed, now: failed.addingTimeInterval(60 * 60)))
        XCTAssertTrue(UpdateSchedule.mayRetry(after: failed, now: failed.addingTimeInterval(-60)), "a clock set back does not block checks")
    }

    func testASkippedVersionIsNotOfferedAutomaticallyButANewerOneIs() throws {
        let skipped = try XCTUnwrap(ReleaseVersion("1.3.0"))
        XCTAssertTrue(UpdateSchedule.offersAutomatically(try XCTUnwrap(ReleaseVersion("1.3.0")), skipped: nil))
        XCTAssertFalse(UpdateSchedule.offersAutomatically(try XCTUnwrap(ReleaseVersion("1.3")), skipped: skipped))
        XCTAssertTrue(UpdateSchedule.offersAutomatically(try XCTUnwrap(ReleaseVersion("1.3.1")), skipped: skipped))
    }
}

// MARK: - Verification and installing

nonisolated final class UpdateVerificationTests: XCTestCase {
    private let key = Curve25519.Signing.PrivateKey()
    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    private func signature(of data: Data) throws -> String {
        try key.signature(for: data).base64EncodedString() + "\n"
    }

    func testDigestsParse() {
        XCTAssertEqual(UpdateVerification.sha256(fromDigest: "sha256:BF43696D4B5AC70ABF0D57CDDBD2994D24B9A629F8C56183FB0AA1142BD8A542"), "bf43696d4b5ac70abf0d57cddbd2994d24b9a629f8c56183fb0aa1142bd8a542")
        XCTAssertNil(UpdateVerification.sha256(fromDigest: nil))
        XCTAssertNil(UpdateVerification.sha256(fromDigest: "sha512:abc"))
        XCTAssertNil(UpdateVerification.sha256(fromDigest: "sha256:not-hex"))
    }

    func testASignedImageWithTheRightChecksumPasses() throws {
        let data = Data("disk image".utf8)
        let asset = UpdateFixtures.asset("Hashlight-1.3.0.dmg", size: Int64(data.count), digest: "sha256:" + UpdateVerification.sha256Hex(of: data))
        XCTAssertNoThrow(try UpdateVerification.verifyDiskImage(data, asset: asset, signatureText: try signature(of: data), publicKeyBase64: publicKey))
        let withoutDigest = UpdateFixtures.asset("Hashlight-1.3.0.dmg", size: Int64(data.count))
        XCTAssertNoThrow(try UpdateVerification.verifyDiskImage(data, asset: withoutDigest, signatureText: try signature(of: data), publicKeyBase64: publicKey))
    }

    func testEveryMismatchStopsTheInstall() throws {
        let data = Data("disk image".utf8)
        let good = UpdateFixtures.asset("Hashlight-1.3.0.dmg", size: Int64(data.count), digest: "sha256:" + UpdateVerification.sha256Hex(of: data))
        let signature = try signature(of: data)

        XCTAssertThrowsError(try UpdateVerification.verifyDiskImage(data.dropLast(), asset: good, signatureText: signature, publicKeyBase64: publicKey)) {
            XCTAssertEqual($0 as? UpdateError, .downloadIncomplete)
        }
        let otherDigest = UpdateFixtures.asset("Hashlight-1.3.0.dmg", size: Int64(data.count), digest: "sha256:" + String(repeating: "0", count: 64))
        XCTAssertThrowsError(try UpdateVerification.verifyDiskImage(data, asset: otherDigest, signatureText: signature, publicKeyBase64: publicKey)) {
            XCTAssertEqual($0 as? UpdateError, .checksumMismatch)
        }
        let otherKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        XCTAssertThrowsError(try UpdateVerification.verifyDiskImage(data, asset: good, signatureText: signature, publicKeyBase64: otherKey)) {
            XCTAssertEqual($0 as? UpdateError, .signatureInvalid)
        }
        var tampered = data
        tampered[0] ^= 1
        let tamperedAsset = UpdateFixtures.asset("Hashlight-1.3.0.dmg", size: Int64(tampered.count))
        XCTAssertThrowsError(try UpdateVerification.verifyDiskImage(tampered, asset: tamperedAsset, signatureText: signature, publicKeyBase64: publicKey)) {
            XCTAssertEqual($0 as? UpdateError, .signatureInvalid)
        }
        XCTAssertFalse(UpdateVerification.isValidSignature("not base64", of: data, publicKeyBase64: publicKey))
        XCTAssertFalse(UpdateVerification.isValidSignature(signature, of: data, publicKeyBase64: "AAAA"))
    }

    func testTheCopiedAppMustBeHashlightAtTheReleasedVersion() throws {
        let version = try XCTUnwrap(ReleaseVersion("1.3.0"))
        let sonoma = OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0)

        let good = try UpdateFixtures.makeApp(version: "1.3.0")
        defer { try? FileManager.default.removeItem(at: good.deletingLastPathComponent()) }
        XCTAssertNoThrow(try UpdateVerification.verifyApp(at: good, bundleIdentifier: "io.github.ib0ndar.hashlight", version: version, operatingSystem: sonoma, checkCodeSignature: false))

        XCTAssertThrowsError(try UpdateVerification.verifyApp(at: good, bundleIdentifier: "io.github.ib0ndar.hashlight.debug", version: version, operatingSystem: sonoma, checkCodeSignature: false)) {
            XCTAssertEqual($0 as? UpdateError, .wrongApp("io.github.ib0ndar.hashlight"))
        }
        XCTAssertThrowsError(try UpdateVerification.verifyApp(at: good, bundleIdentifier: "io.github.ib0ndar.hashlight", version: try XCTUnwrap(ReleaseVersion("1.3.1")), operatingSystem: sonoma, checkCodeSignature: false)) {
            XCTAssertEqual($0 as? UpdateError, .wrongVersion(found: "1.3.0", expected: "1.3.1"))
        }

        let needsTahoe = try UpdateFixtures.makeApp(version: "1.3.0", minimumSystem: "26.0")
        defer { try? FileManager.default.removeItem(at: needsTahoe.deletingLastPathComponent()) }
        XCTAssertThrowsError(try UpdateVerification.verifyApp(at: needsTahoe, bundleIdentifier: "io.github.ib0ndar.hashlight", version: version, operatingSystem: sonoma, checkCodeSignature: false)) {
            XCTAssertEqual($0 as? UpdateError, .needsNewerMacOS("26.0"))
        }

        XCTAssertThrowsError(try UpdateVerification.verifyApp(at: good.deletingLastPathComponent().appendingPathComponent("Missing.app"), bundleIdentifier: "io.github.ib0ndar.hashlight", version: version, checkCodeSignature: false)) {
            XCTAssertEqual($0 as? UpdateError, .appMissingFromDiskImage)
        }
    }

    func testMinimumSystemVersions() {
        let system = OperatingSystemVersion(majorVersion: 15, minorVersion: 2, patchVersion: 0)
        XCTAssertTrue(UpdateVerification.isSatisfied("13.0", by: system))
        XCTAssertTrue(UpdateVerification.isSatisfied("15.2", by: system))
        XCTAssertFalse(UpdateVerification.isSatisfied("15.3", by: system))
        XCTAssertFalse(UpdateVerification.isSatisfied("26", by: system))
    }

    func testCodeSignaturesAreChecked() throws {
        XCTAssertTrue(UpdateVerification.hasValidCodeSignature(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        let unsigned = try UpdateFixtures.makeApp()
        defer { try? FileManager.default.removeItem(at: unsigned.deletingLastPathComponent()) }
        XCTAssertFalse(UpdateVerification.hasValidCodeSignature(unsigned))
    }

    func testInstallLocations() throws {
        XCTAssertEqual(UpdateInstallLocation.problem(for: URL(fileURLWithPath: "/private/var/folders/xy/T/AppTranslocation/1234/d/Hashlight.app")), .translocated)
        // The sealed system volume does not report itself read-only; a mounted disk image does.
        XCTAssertEqual(UpdateInstallLocation.problem(for: URL(fileURLWithPath: "/System/Applications/Calculator.app")), .locationNotWritable)
        let app = try UpdateFixtures.makeApp()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        XCTAssertNil(UpdateInstallLocation.problem(for: app))
    }

    @MainActor
    func testPreflightNeedsAReleaseBuildAKeyAndBothAssets() throws {
        let app = try UpdateFixtures.makeApp()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let current = try XCTUnwrap(ReleaseVersion("1.2.0"))
        let complete = try XCTUnwrap(UpdateFeed.availableUpdate(
            in: [UpdateFixtures.release("v1.3.0", assets: [UpdateFixtures.asset("Hashlight-1.3.0.dmg"), UpdateFixtures.asset("Hashlight-1.3.0.dmg.sig")])],
            current: current
        ))
        let unsigned = try XCTUnwrap(UpdateFeed.availableUpdate(
            in: [UpdateFixtures.release("v1.3.0", assets: [UpdateFixtures.asset("Hashlight-1.3.0.dmg")])],
            current: current
        ))
        let empty = try XCTUnwrap(UpdateFeed.availableUpdate(in: [UpdateFixtures.release("v1.3.0")], current: current))

        XCTAssertNil(UpdateInstaller.preflightProblem(for: complete, appURL: app, publicKey: publicKey, isDevelopmentBuild: false))
        XCTAssertEqual(UpdateInstaller.preflightProblem(for: complete, appURL: app, publicKey: publicKey, isDevelopmentBuild: true), .developmentBuild)
        XCTAssertEqual(UpdateInstaller.preflightProblem(for: complete, appURL: app, publicKey: "", isDevelopmentBuild: false), .noUpdateKey)
        XCTAssertEqual(UpdateInstaller.preflightProblem(for: complete, appURL: app, publicKey: nil, isDevelopmentBuild: false), .noUpdateKey)
        XCTAssertEqual(UpdateInstaller.preflightProblem(for: unsigned, appURL: app, publicKey: publicKey, isDevelopmentBuild: false), .missingSignature)
        XCTAssertEqual(UpdateInstaller.preflightProblem(for: empty, appURL: app, publicKey: publicKey, isDevelopmentBuild: false), .missingDiskImage)
    }

    func testTheBundlesAreExchangedInOneStep() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-exchange-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = folder.appendingPathComponent("Applications/Hashlight.app")
        let staged = folder.appendingPathComponent("work/Hashlight.app")
        for (bundle, marker) in [(installed, "old"), (staged, "new")] {
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: bundle.appendingPathComponent("marker"))
        }

        try UpdateInstaller.exchange(staged, with: installed)

        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("marker"), encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: staged.appendingPathComponent("marker"), encoding: .utf8), "old", "the replaced app stays in the work folder")
    }

    func testTheBuiltAppCarriesTheUpdateKeyAndFeed() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let key = try XCTUnwrap(info["HashlightUpdatePublicKey"] as? String)
        XCTAssertEqual(Data(base64Encoded: key)?.count, 32, "HASHLIGHT_UPDATE_PUBLIC_KEY is an Ed25519 public key")
        XCTAssertEqual(info["HashlightUpdateFeedURL"] as? String, "https://api.github.com/repos/ib0ndar/Hashlight/releases?per_page=20")
    }
}

// MARK: - Relaunch

nonisolated final class UpdateRelaunchStateTests: XCTestCase {
    private func scratchDefaults() -> (UserDefaults, String) {
        let name = "io.github.ib0ndar.hashlight.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    func testTheStateIsTakenOnce() {
        let (defaults, name) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        let state = UpdateRelaunchState(documentPaths: ["/tmp/a.md", "/tmp/b.md"], selectedPath: "/tmp/b.md", cleanupPath: "/tmp/TemporaryItems/x", savedAt: saved)
        state.save(to: defaults)

        XCTAssertEqual(UpdateRelaunchState.take(from: defaults, now: saved.addingTimeInterval(5)), state)
        XCTAssertNil(UpdateRelaunchState.take(from: defaults, now: saved.addingTimeInterval(6)))
    }

    func testAStaleStateIsIgnoredAndRemoved() {
        let (defaults, name) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        UpdateRelaunchState(documentPaths: [], selectedPath: nil, cleanupPath: nil, savedAt: saved).save(to: defaults)

        XCTAssertNil(UpdateRelaunchState.take(from: defaults, now: saved.addingTimeInterval(UpdateRelaunchState.maximumAge + 1)))
        XCTAssertNil(defaults.object(forKey: UpdateRelaunchState.defaultsKey))
    }
}

// MARK: - Controller

@MainActor
private final class RecordingPresenter: UpdatePresenting {
    var offers = 0
    var closes = 0
    var upToDate: [String] = []
    var failures: [String] = []

    func showOffer() { offers += 1 }
    func closeOffer() { closes += 1 }
    func showUpToDate(version: String) { upToDate.append(version) }
    func showCheckFailure(_ message: String) { failures.append(message) }
}

@MainActor
private final class ControllerHarness {
    let presenter = RecordingPresenter()
    let defaultsName = "io.github.ib0ndar.hashlight.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let app: URL
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var releases: [GitHubRelease] = []
    var fetchError: Error?
    var fetches = 0
    var isActive = true
    var isEnabled = true
    private(set) var controller: UpdateController!

    init(version: String = "1.2.0") throws {
        defaults = UserDefaults(suiteName: defaultsName)!
        app = try UpdateFixtures.makeApp(version: version)
        controller = UpdateController(
            defaults: defaults,
            bundle: try XCTUnwrap(Bundle(url: app)),
            now: { [weak self] in self?.now ?? Date() },
            fetchReleases: { [weak self] _ in
                guard let self else { throw CancellationError() }
                self.fetches += 1
                if let fetchError = self.fetchError { throw fetchError }
                return self.releases
            },
            allowsAutomaticChecks: true,
            isAutomaticCheckEnabled: { [weak self] in self?.isEnabled ?? false },
            isAppActive: { [weak self] in self?.isActive ?? false },
            isDevelopmentBuild: false,
            presenter: presenter
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
    }
}

nonisolated final class UpdateControllerTests: XCTestCase {
    private static func releases(_ tags: String...) -> [GitHubRelease] {
        tags.map { UpdateFixtures.release($0) }
    }

    @MainActor
    func testAManualCheckReportsUpToDateAndRecordsTheCheck() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        harness.releases = Self.releases("v1.2.0", "v1.1.0")

        await harness.controller.check(userInitiated: true)

        XCTAssertEqual(harness.presenter.upToDate, ["1.2.0"])
        XCTAssertEqual(harness.presenter.offers, 0)
        XCTAssertEqual(harness.defaults.object(forKey: DefaultsKeys.lastUpdateCheck) as? Date, harness.now)
        XCTAssertEqual(harness.controller.lastCheckDate, harness.now)
        XCTAssertNil(harness.controller.availableVersion)
    }

    @MainActor
    func testAManualCheckOffersEvenASkippedVersion() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        harness.releases = Self.releases("v1.3.0", "v1.2.0")
        harness.defaults.set("1.3.0", forKey: DefaultsKeys.skippedUpdateVersion)

        await harness.controller.check(userInitiated: true)

        XCTAssertEqual(harness.presenter.offers, 1)
        XCTAssertEqual(harness.controller.offeredUpdate?.version.text, "1.3.0")
        XCTAssertEqual(harness.controller.availableVersion, "1.3.0")
    }

    @MainActor
    func testAnAutomaticCheckIsSilentWithoutAnUpdateOrForASkippedVersion() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        harness.releases = Self.releases("v1.2.0")
        await harness.controller.check(userInitiated: false)
        XCTAssertEqual(harness.presenter.upToDate, [])
        XCTAssertNotNil(harness.controller.lastCheckDate, "a silent check still counts as today's check")

        harness.releases = Self.releases("v1.3.0", "v1.2.0")
        harness.defaults.set("1.3.0", forKey: DefaultsKeys.skippedUpdateVersion)
        await harness.controller.check(userInitiated: false)
        XCTAssertEqual(harness.presenter.offers, 0)
        XCTAssertNil(harness.controller.offeredUpdate)

        harness.releases = Self.releases("v1.3.1", "v1.3.0", "v1.2.0")
        await harness.controller.check(userInitiated: false)
        XCTAssertEqual(harness.presenter.offers, 1, "a version newer than the skipped one is offered")
        XCTAssertEqual(harness.controller.offeredUpdate?.newerReleases.map(\.tagName), ["v1.3.1", "v1.3.0"])
    }

    @MainActor
    func testAnAutomaticOfferWaitsUntilHashlightIsActive() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        harness.releases = Self.releases("v1.3.0")
        harness.isActive = false

        await harness.controller.check(userInitiated: false)

        XCTAssertEqual(harness.presenter.offers, 0)
        XCTAssertEqual(harness.controller.offeredUpdate?.version.text, "1.3.0")
    }

    @MainActor
    func testAutomaticChecksRunOnceADayAndOnlyWhenOn() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        harness.releases = Self.releases("v1.2.0")

        harness.isEnabled = false
        XCTAssertFalse(harness.controller.checkAutomaticallyIfDue())

        harness.isEnabled = true
        await harness.controller.check(userInitiated: false)
        XCTAssertFalse(harness.controller.checkAutomaticallyIfDue(), "already checked today")
        XCTAssertEqual(harness.fetches, 1)

        harness.now = harness.now.addingTimeInterval(24 * 60 * 60)
        XCTAssertTrue(harness.controller.checkAutomaticallyIfDue())
        await harness.controller.automaticCheck?.value
        XCTAssertEqual(harness.fetches, 2)
        XCTAssertEqual(harness.controller.lastCheckDate, harness.now)
    }

    @MainActor
    func testFailuresAreSilentAutomaticallyAndReportedManually() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        harness.fetchError = UpdateError.rateLimited

        await harness.controller.check(userInitiated: false)
        XCTAssertEqual(harness.presenter.failures, [])
        XCTAssertNil(harness.controller.lastCheckDate, "only a successful check counts")
        XCTAssertFalse(harness.controller.checkAutomaticallyIfDue(), "retried after an hour, not at once")
        harness.now = harness.now.addingTimeInterval(UpdateSchedule.retryInterval)
        XCTAssertTrue(harness.controller.checkAutomaticallyIfDue())
        await harness.controller.automaticCheck?.value
        XCTAssertEqual(harness.fetches, 2)
        XCTAssertEqual(harness.presenter.failures, [], "the retry fails silently too")

        await harness.controller.check(userInitiated: true)
        XCTAssertEqual(harness.presenter.failures, [UpdateError.rateLimited.localizedDescription])
    }

    @MainActor
    func testSkipRemembersTheVersionAndClosesTheWindow() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        harness.releases = Self.releases("v1.3.0")
        await harness.controller.check(userInitiated: true)

        harness.controller.skipOfferedVersion()

        XCTAssertEqual(harness.defaults.string(forKey: DefaultsKeys.skippedUpdateVersion), "1.3.0")
        XCTAssertEqual(harness.presenter.closes, 1)
        XCTAssertNil(harness.controller.offeredUpdate)
    }

    @MainActor
    func testRemindLaterDoesNotSkip() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        harness.releases = Self.releases("v1.3.0")
        await harness.controller.check(userInitiated: true)

        harness.controller.remindLater()

        XCTAssertNil(harness.defaults.string(forKey: DefaultsKeys.skippedUpdateVersion))
        XCTAssertEqual(harness.presenter.closes, 1)
    }

    @MainActor
    func testAnUpdateWithoutASignatureIsNotInstalled() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        harness.releases = [UpdateFixtures.release("v1.3.0", assets: [UpdateFixtures.asset("Hashlight-1.3.0.dmg")])]
        await harness.controller.check(userInitiated: true)

        harness.controller.installOfferedUpdate()

        guard case .failed(let message, let canOpenReleasePage) = harness.controller.installState else {
            return XCTFail("expected a failure, got \(harness.controller.installState)")
        }
        XCTAssertEqual(message, UpdateError.missingSignature.localizedDescription)
        XCTAssertTrue(canOpenReleasePage)
        harness.controller.dismissInstallFailure()
        XCTAssertEqual(harness.controller.installState, .idle)
    }

    @MainActor
    func testTheStatusLineSaysWhenTheLastCheckWas() async throws {
        let harness = try ControllerHarness()
        defer { harness.cleanUp() }
        XCTAssertEqual(harness.controller.statusText, "Not checked yet.")
        harness.now = Date()
        harness.releases = Self.releases("v1.3.0")
        await harness.controller.check(userInitiated: false)
        XCTAssertTrue(harness.controller.statusText.hasPrefix("Last checked "), harness.controller.statusText)
        XCTAssertTrue(harness.controller.statusText.hasSuffix("Hashlight 1.3.0 is available."), harness.controller.statusText)
    }
}

nonisolated final class AutomaticUpdateSettingTests: XCTestCase {
    @MainActor
    func testAutomaticChecksAreOnUnlessTurnedOff() {
        let name = "io.github.ib0ndar.hashlight.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(SettingsManager.loadAutomaticallyChecksForUpdates(from: defaults))
        defaults.set(false, forKey: DefaultsKeys.automaticallyChecksForUpdates)
        XCTAssertFalse(SettingsManager.loadAutomaticallyChecksForUpdates(from: defaults))
    }

    @MainActor
    func testTestRunsNeverCheckOnTheirOwn() {
        XCTAssertFalse(UpdateController.automaticChecksAllowed)
    }
}
