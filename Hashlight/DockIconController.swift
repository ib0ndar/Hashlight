import AppKit
import Combine

/// Chooses the icon the Dock and the app switcher show while Hashlight runs.
///
/// Only `NSApp.applicationIconImage` changes. The bundle's icon on disk is never rewritten (that
/// would break the code signature), so Finder, Launchpad, and the Dock tile of a quit app always
/// show the bundle icon.
final class DockIconController: ObservableObject {
    static let shared = DockIconController()

    static let frostImageName = "DockIcon-Frost"
    static let emberImageName = "DockIcon-Ember"

    /// The icon the welcome screen and Settings → About draw: the one the Dock shows.
    @Published private(set) var image: NSImage
    /// The bundled icon currently applied, or nil while macOS supplies the icon.
    private(set) var appliedImageName: String?

    private var mode: SettingsManager.DockIconMode = .system
    private var modeSubscription: AnyCancellable?
    private var systemAppearanceObserver: NSObjectProtocol?

    private init() {
        image = Self.currentApplicationIcon()
    }

    /// True on macOS 26 and later, where the system's icon style (System Settings → Appearance →
    /// Icon & widget style) already switches the app icon, including Clear and Tinted.
    static var systemStylesAppIcon: Bool {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    /// The system's Light/Dark setting, independent of the app's own appearance override.
    /// `AppleInterfaceStyle` is absent in Light mode.
    static var systemIsDark: Bool {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return global?["AppleInterfaceStyle"] as? String == "Dark"
    }

    /// The bundled icon for `mode`, or nil to leave the icon to macOS.
    static func imageName(
        for mode: SettingsManager.DockIconMode,
        systemStylesAppIcon: Bool,
        systemIsDark: Bool
    ) -> String? {
        switch mode {
        case .frost:
            return frostImageName
        case .ember:
            return emberImageName
        case .system:
            if systemStylesAppIcon {
                return nil
            }
            return systemIsDark ? emberImageName : frostImageName
        }
    }

    /// Applies the saved mode now and again whenever it changes.
    func start(observing settings: SettingsManager) {
        modeSubscription = settings.$dockIconMode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.apply(mode)
            }
    }

    func apply(_ mode: SettingsManager.DockIconMode) {
        self.mode = mode
        let systemStylesAppIcon = Self.systemStylesAppIcon
        followSystemAppearance(mode == .system && !systemStylesAppIcon)

        let name = Self.imageName(
            for: mode,
            systemStylesAppIcon: systemStylesAppIcon,
            systemIsDark: Self.systemIsDark
        )
        let icon = name.flatMap { Bundle.main.image(forResource: $0) }
        // Assigning nil restores the bundle icon.
        NSApplication.shared.applicationIconImage = icon
        appliedImageName = icon == nil ? nil : name
        image = icon ?? Self.currentApplicationIcon()
    }

    /// A copy of the running app's icon. The getter returns one shared image that AppKit redraws
    /// in place when the icon changes, which SwiftUI would not notice.
    private static func currentApplicationIcon() -> NSImage {
        let icon: NSImage = NSApplication.shared.applicationIconImage
        return icon.copy() as? NSImage ?? icon
    }

    private func followSystemAppearance(_ follow: Bool) {
        let center = DistributedNotificationCenter.default()
        if follow {
            guard systemAppearanceObserver == nil else { return }
            // Posted when the system switches between Light and Dark, including automatic switches.
            systemAppearanceObserver = center.addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.apply(self.mode)
                }
            }
        } else if let observer = systemAppearanceObserver {
            center.removeObserver(observer)
            systemAppearanceObserver = nil
        }
    }
}
