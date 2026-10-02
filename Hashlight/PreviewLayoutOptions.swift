import Foundation

// The preview's layout settings (Settings → Viewing and the status bar). They live outside
// SettingsManager, which keeps typealiases for them, because the Quick Look extension lays out
// the same preview with fixed values and cannot compile SettingsManager.

/// Horizontal placement of the preview's text column. This positions the whole column
/// within the pane — text inside the column stays left-aligned (it is not paragraph
/// alignment). Only visible when the pane is wider than the column plus its margins;
/// in narrow panes and Focus Mode all three settings look the same.
enum PreviewContentAlignment: String, CaseIterable {
    case left = "Left"
    case center = "Center"
    case right = "Right"

    var displayName: String {
        return self.rawValue
    }

    var icon: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}

/// Maximum width of the preview's text column. A MAXIMUM, not a fixed size: the column
/// always shrinks to fit a narrower pane (Focus Mode, a small window). `.full` tracks the pane.
enum PreviewContentWidth: String, CaseIterable {
    case narrow = "Narrow"
    case medium = "Medium"
    case wide = "Wide"
    case full = "Full"

    var displayName: String {
        return self.rawValue
    }

    /// Column width in points; nil = fill the pane without a maximum.
    var points: CGFloat? {
        switch self {
        case .narrow: return 760
        case .medium: return 960
        case .wide: return 1300
        case .full: return nil
        }
    }

    /// Preset cap for images and diagrams, which are sized once at build time. Full has
    /// no artificial cap, matching the text column's fill-the-pane behavior.
    var attachmentMaxWidth: CGFloat? {
        points.map { max(200, $0 - 100) }
    }
}

enum PreviewPageMargin: String, CaseIterable {
    case compact = "Compact"
    case normal = "Normal"
    case comfortable = "Comfortable"

    var points: CGFloat {
        switch self {
        case .compact: return 16
        case .normal: return 24
        case .comfortable: return 40
        }
    }
}
