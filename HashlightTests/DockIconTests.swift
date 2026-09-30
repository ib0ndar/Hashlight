import XCTest
@testable import Hashlight

nonisolated final class DockIconTests: XCTestCase {
    @MainActor
    func testSystemModeLeavesTheIconToMacOSWhereTheSystemStylesAppIcons() {
        for systemIsDark in [false, true] {
            XCTAssertNil(DockIconController.imageName(for: .system, systemStylesAppIcon: true, systemIsDark: systemIsDark))
        }
    }

    @MainActor
    func testSystemModeFollowsTheSystemLightDarkSettingBeforeMacOS26() {
        XCTAssertEqual(
            DockIconController.imageName(for: .system, systemStylesAppIcon: false, systemIsDark: false),
            DockIconController.frostImageName
        )
        XCTAssertEqual(
            DockIconController.imageName(for: .system, systemStylesAppIcon: false, systemIsDark: true),
            DockIconController.emberImageName
        )
    }

    @MainActor
    func testFrostAndEmberOverrideTheSystemEverywhere() {
        for systemStylesAppIcon in [false, true] {
            for systemIsDark in [false, true] {
                XCTAssertEqual(
                    DockIconController.imageName(for: .frost, systemStylesAppIcon: systemStylesAppIcon, systemIsDark: systemIsDark),
                    DockIconController.frostImageName
                )
                XCTAssertEqual(
                    DockIconController.imageName(for: .ember, systemStylesAppIcon: systemStylesAppIcon, systemIsDark: systemIsDark),
                    DockIconController.emberImageName
                )
            }
        }
    }

    @MainActor
    func testBundledDockIconsCarryEverySize() throws {
        for name in [DockIconController.frostImageName, DockIconController.emberImageName] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "icns"), name)
            let image = try XCTUnwrap(NSImage(contentsOf: url), name)
            let widths = Set(image.representations.map(\.pixelsWide))
            XCTAssertTrue(Set([16, 32, 64, 128, 256, 512, 1024]).isSubset(of: widths), "\(name): \(widths.sorted())")
        }
    }

    @MainActor
    func testDockIconModeDefaultsToSystemAndPersists() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: DefaultsKeys.dockIconMode)
        let settings = SettingsManager.shared
        let previous = settings.dockIconMode
        defer {
            settings.dockIconMode = previous
            defaults.set(saved, forKey: DefaultsKeys.dockIconMode)
        }

        defaults.removeObject(forKey: DefaultsKeys.dockIconMode)
        XCTAssertEqual(SettingsManager().dockIconMode, .system)

        settings.dockIconMode = .ember
        XCTAssertEqual(defaults.string(forKey: DefaultsKeys.dockIconMode), "Ember")
        XCTAssertEqual(SettingsManager().dockIconMode, .ember)

        defaults.set("Unknown", forKey: DefaultsKeys.dockIconMode)
        XCTAssertEqual(SettingsManager().dockIconMode, .system)
    }

    @MainActor
    func testApplyingAModePublishesANewImageForTheWelcomeScreenAndAbout() {
        let controller = DockIconController.shared
        defer { controller.apply(SettingsManager.shared.dockIconMode) }

        controller.apply(.ember)
        let emberImage = controller.image
        XCTAssertEqual(controller.appliedImageName, DockIconController.emberImageName)
        XCTAssertEqual(emberImage.representations.map(\.pixelsWide).max(), 1024)

        controller.apply(.frost)
        let frostImage = controller.image
        XCTAssertEqual(controller.appliedImageName, DockIconController.frostImageName)
        XCTAssertFalse(frostImage === emberImage)

        controller.apply(.system)
        let expected = DockIconController.imageName(
            for: .system,
            systemStylesAppIcon: DockIconController.systemStylesAppIcon,
            systemIsDark: DockIconController.systemIsDark
        )
        XCTAssertEqual(controller.appliedImageName, expected)
        XCTAssertFalse(controller.image === frostImage)
    }
}
