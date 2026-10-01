import XCTest
import SwiftUI
@testable import Hashlight

/// A throwaway preferences domain, removed again when the test ends.
private nonisolated final class ScratchDefaults {
    let name = "io.github.ib0ndar.hashlight.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

nonisolated final class NavigatorSettingsTests: XCTestCase {
    @MainActor
    func testShownOutlineMigratesToAVisibleOutlineNavigator() {
        let scratch = ScratchDefaults()
        scratch.defaults.set(true, forKey: DefaultsKeys.legacyShowOutline)

        let state = SettingsManager.loadNavigatorState(from: scratch.defaults)

        XCTAssertEqual(state.mode, .outline)
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(scratch.defaults.string(forKey: DefaultsKeys.navigatorMode), "outline")
        XCTAssertEqual(scratch.defaults.object(forKey: DefaultsKeys.navigatorVisible) as? Bool, true)
        XCTAssertNil(scratch.defaults.object(forKey: DefaultsKeys.legacyShowOutline), "the legacy key is removed after migrating")
    }

    @MainActor
    func testHiddenOutlineMigratesToAHiddenNavigator() {
        let scratch = ScratchDefaults()
        scratch.defaults.set(false, forKey: DefaultsKeys.legacyShowOutline)

        let state = SettingsManager.loadNavigatorState(from: scratch.defaults)

        XCTAssertEqual(state.mode, .outline)
        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(scratch.defaults.object(forKey: DefaultsKeys.navigatorVisible) as? Bool, false)
        XCTAssertNil(scratch.defaults.object(forKey: DefaultsKeys.legacyShowOutline))
    }

    @MainActor
    func testAnOpenFolderWithTheOutlineHiddenMigratesToVisibleFiles() {
        let scratch = ScratchDefaults()
        scratch.defaults.set(false, forKey: DefaultsKeys.legacyShowOutline)
        scratch.defaults.set(Data([1, 2, 3]), forKey: DefaultsKeys.folderBookmark)

        let state = SettingsManager.loadNavigatorState(from: scratch.defaults)

        XCTAssertEqual(state.mode, .files)
        XCTAssertTrue(state.isVisible)
    }

    @MainActor
    func testAFreshInstallStartsWithTheOutlineNavigatorHiddenAndWritesNothing() {
        let scratch = ScratchDefaults()

        let state = SettingsManager.loadNavigatorState(from: scratch.defaults)

        XCTAssertEqual(state.mode, .outline)
        XCTAssertFalse(state.isVisible)
        XCTAssertNil(scratch.defaults.object(forKey: DefaultsKeys.navigatorMode))
        XCTAssertNil(scratch.defaults.object(forKey: DefaultsKeys.navigatorVisible))
    }

    @MainActor
    func testSavedNavigatorSettingsWinOverTheLegacyKey() {
        let scratch = ScratchDefaults()
        scratch.defaults.set("files", forKey: DefaultsKeys.navigatorMode)
        scratch.defaults.set(false, forKey: DefaultsKeys.navigatorVisible)
        scratch.defaults.set(true, forKey: DefaultsKeys.legacyShowOutline)

        let state = SettingsManager.loadNavigatorState(from: scratch.defaults)

        XCTAssertEqual(state.mode, .files)
        XCTAssertFalse(state.isVisible)
    }

    @MainActor
    func testAFocusModeCollapseIsNotRestoredAsTheSavedSidebarState() {
        let collapsed = [
            "0.000000, 0.000000, 330.000000, 700.000000, YES, NO",
            "0.000000, 0.000000, 1000.000000, 700.000000, NO, NO"
        ]
        XCTAssertEqual(SidebarAutosave.framesWithSidebarExpanded(collapsed), [
            "0.000000, 0.000000, 330.000000, 700.000000, NO, NO",
            "0.000000, 0.000000, 1000.000000, 700.000000, NO, NO"
        ])
        // Already expanded, or a format this does not know: left alone.
        XCTAssertNil(SidebarAutosave.framesWithSidebarExpanded([collapsed[1]]))
        XCTAssertNil(SidebarAutosave.framesWithSidebarExpanded(["0, 0, 330, 700, YES"]))
        XCTAssertNil(SidebarAutosave.framesWithSidebarExpanded([]))
    }

    @MainActor
    func testNavigatorSettingsPersistInTheStandardDefaults() {
        let defaults = UserDefaults.standard
        let savedMode = defaults.object(forKey: DefaultsKeys.navigatorMode)
        let savedVisibility = defaults.object(forKey: DefaultsKeys.navigatorVisible)
        let settings = SettingsManager.shared
        let previousMode = settings.navigatorMode
        let previousVisibility = settings.isNavigatorVisible
        defer {
            settings.navigatorMode = previousMode
            settings.isNavigatorVisible = previousVisibility
            defaults.set(savedMode, forKey: DefaultsKeys.navigatorMode)
            defaults.set(savedVisibility, forKey: DefaultsKeys.navigatorVisible)
        }

        settings.showNavigator(.files)
        XCTAssertEqual(defaults.string(forKey: DefaultsKeys.navigatorMode), "files")
        XCTAssertEqual(defaults.object(forKey: DefaultsKeys.navigatorVisible) as? Bool, true)
        XCTAssertEqual(SettingsManager().navigatorMode, .files)

        settings.toggleNavigator()
        XCTAssertEqual(defaults.object(forKey: DefaultsKeys.navigatorVisible) as? Bool, false)
        XCTAssertFalse(SettingsManager().isNavigatorVisible)
    }
}

nonisolated final class FrontmatterSettingTests: XCTestCase {
    @MainActor
    func testFrontmatterIsShownUnlessTurnedOff() {
        let scratch = ScratchDefaults()
        XCTAssertEqual(DefaultsKeys.showsFrontmatter, "showsFrontmatter")
        XCTAssertTrue(SettingsManager.loadShowsFrontmatter(from: scratch.defaults), "on by default")
        XCTAssertNil(scratch.defaults.object(forKey: DefaultsKeys.showsFrontmatter), "the default writes nothing")

        scratch.defaults.set(false, forKey: DefaultsKeys.showsFrontmatter)
        XCTAssertFalse(SettingsManager.loadShowsFrontmatter(from: scratch.defaults))

        scratch.defaults.set("yes", forKey: DefaultsKeys.showsFrontmatter)
        XCTAssertTrue(SettingsManager.loadShowsFrontmatter(from: scratch.defaults), "a value of the wrong type falls back to on")
    }
}

nonisolated final class SettingsPaneTests: XCTestCase {
    @MainActor
    func testThePaneKeyAndValuesAreStable() {
        XCTAssertEqual(DefaultsKeys.settingsPane, "settingsPane")
        XCTAssertEqual(SettingsPane.allCases.map(\.rawValue), ["general", "viewing", "tables"])
    }

    @MainActor
    func testTheLastPaneIsRestoredAndUnknownValuesFallBackToGeneral() {
        let scratch = ScratchDefaults()
        let storage = AppStorage(wrappedValue: SettingsPane.general, DefaultsKeys.settingsPane, store: scratch.defaults)
        XCTAssertEqual(storage.wrappedValue, .general)

        scratch.defaults.set(SettingsPane.tables.rawValue, forKey: DefaultsKeys.settingsPane)
        XCTAssertEqual(storage.wrappedValue, .tables)

        // The former About pane no longer exists.
        scratch.defaults.set("about", forKey: DefaultsKeys.settingsPane)
        XCTAssertEqual(storage.wrappedValue, .general)
    }

    @MainActor
    func testEachPaneSizesTheWindowToItsOwnContent() {
        let heights = SettingsPane.allCases.map(\.height)
        XCTAssertEqual(Set(heights).count, SettingsPane.allCases.count)
        XCTAssertTrue(heights.allSatisfy { $0 > 0 && $0 < 700 })
    }
}

nonisolated final class TableCategoryEditingTests: XCTestCase {
    private let defaults = MarkdownTableColumnConfiguration.defaults

    private func ids(_ configuration: MarkdownTableColumnConfiguration) -> [String] {
        configuration.categories.map(\.id)
    }

    func testMovingUpAndDownSwapsNeighboursAndStopsAtTheEnds() {
        let movedDown = defaults.movingCategory(withID: "descriptive", by: 1)
        XCTAssertEqual(ids(movedDown), ["operational-documentation", "descriptive", "compact", "identifier", "other"])

        let movedUp = movedDown.movingCategory(withID: "descriptive", by: -1)
        XCTAssertEqual(movedUp, defaults)

        XCTAssertEqual(defaults.movingCategory(withID: "descriptive", by: -1), defaults)
        XCTAssertEqual(defaults.movingCategory(withID: "other", by: 1), defaults)
        XCTAssertEqual(defaults.movingCategory(withID: "missing", by: 1), defaults)
    }

    func testDraggingInsertsAtTheDropIndex() {
        // Dropping "Other" before the first row.
        XCTAssertEqual(
            ids(defaults.movingCategories(withIDs: ["other"], to: 0)),
            ["other", "descriptive", "operational-documentation", "compact", "identifier"]
        )
        // Dropping the first row after the last one.
        XCTAssertEqual(
            ids(defaults.movingCategories(withIDs: ["descriptive"], to: 5)),
            ["operational-documentation", "compact", "identifier", "other", "descriptive"]
        )
        // Dropping a row between two later rows accounts for its own old position.
        XCTAssertEqual(
            ids(defaults.movingCategories(withIDs: ["descriptive"], to: 3)),
            ["operational-documentation", "compact", "descriptive", "identifier", "other"]
        )
        // Dropping a row where it already is changes nothing.
        XCTAssertEqual(defaults.movingCategories(withIDs: ["compact"], to: 2), defaults)
        XCTAssertEqual(defaults.movingCategories(withIDs: ["missing"], to: 0), defaults)
    }

    func testRemovingKeepsTheBuiltInCategoriesButNotOtherOrCustomOnes() {
        for id in ["descriptive", "operational-documentation", "compact", "identifier"] {
            XCTAssertEqual(defaults.removingCategory(withID: id), defaults, id)
        }

        let withoutOther = defaults.removingCategory(withID: "other")
        XCTAssertFalse(ids(withoutOther).contains("other"))
        // Without Other, unmatched headers fall back to the documented weight.
        XCTAssertEqual(
            MarkdownTableColumnLayout.weight(for: "Unmatched", configuration: withoutOther),
            CGFloat(MarkdownTableColumnConfiguration.fallbackWeight)
        )

        let custom = MarkdownTableColumnCategory(id: "custom", name: "Custom", weight: 3, words: ["vendor"])
        let withCustom = defaults.savingCategory(custom)
        XCTAssertEqual(withCustom.removingCategory(withID: "custom"), defaults)
    }

    func testSavingAddsOrReplacesAndRejectsAnInvalidWeight() throws {
        let added = MarkdownTableColumnConfiguration.newCategory()
        let withNew = defaults.savingCategory(added)
        XCTAssertEqual(withNew.categories.last, added)
        XCTAssertEqual(withNew.categories.count, defaults.categories.count + 1)

        var edited = try XCTUnwrap(defaults.category(withID: "compact"))
        edited.weight = 0.8
        edited.words.append("port")
        let replaced = defaults.savingCategory(edited)
        XCTAssertEqual(replaced.categories.count, defaults.categories.count)
        XCTAssertEqual(replaced.category(withID: "compact"), edited)
        XCTAssertEqual(MarkdownTableColumnLayout.weight(for: "Port", configuration: replaced), 0.8)

        edited.weight = 0
        XCTAssertEqual(defaults.savingCategory(edited), defaults)
    }

    func testRestoringDefaultsReturnsTheBuiltInSet() {
        let edited = defaults
            .removingCategory(withID: "other")
            .movingCategory(withID: "compact", by: -2)
            .savingCategory(MarkdownTableColumnConfiguration.newCategory())
        XCTAssertFalse(edited.isDefault)
        XCTAssertTrue(defaults.isDefault)

        let restored = MarkdownTableColumnConfiguration.defaults
        XCTAssertTrue(restored.isDefault)
        XCTAssertEqual(ids(restored), ["descriptive", "operational-documentation", "compact", "identifier", "other"])
    }
}

nonisolated final class AboutPanelTests: XCTestCase {
    @MainActor
    func testTheCreditsKeepTheZMDAttribution() throws {
        let credits = try XCTUnwrap(AboutPanel.credits())
        XCTAssertTrue(credits.string.contains("Based on zMD by Zachary Rossmiller"), credits.string)
    }

    @MainActor
    func testTheAboutPanelShowsTheDockIconAndTheVersion() {
        let icon = DockIconController.shared.image
        let options = AboutPanel.options(icon: icon)
        XCTAssertTrue((options[.applicationIcon] as? NSImage) === icon)
        XCTAssertEqual(options[.applicationVersion] as? String, Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        XCTAssertNotNil(options[.credits] as? NSAttributedString)
    }
}
