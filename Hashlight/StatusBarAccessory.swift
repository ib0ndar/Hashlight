import SwiftUI
import AppKit

/// Places the status bar as a bottom-aligned split-item accessory on the detail column of the
/// `NSSplitView` that `NavigationSplitView` creates. AppKit then insets the preview's
/// `NSScrollView` for the bar and draws the scroll edge effect where the document passes under
/// it; SwiftUI's `safeAreaBar` applies that effect only to SwiftUI scroll views. Use it as a
/// zero-size view inside the detail column: it finds its own split view item through the view
/// hierarchy SwiftUI builds, and reports through `isAttached` so the caller can fall back to an
/// inline bar if that hierarchy ever changes.
@available(macOS 26, *)
struct StatusBarAccessoryAnchor<Content: View>: NSViewRepresentable {
    let isShown: Bool
    @Binding var isAttached: Bool
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> StatusBarAccessoryAnchorView {
        let view = StatusBarAccessoryAnchorView()
        view.accessory.hostingView.rootView = AnyView(content())
        view.isShown = isShown
        view.onAttachmentChange = { attached in
            DispatchQueue.main.async { isAttached = attached }
        }
        return view
    }

    func updateNSView(_ view: StatusBarAccessoryAnchorView, context: Context) {
        view.accessory.hostingView.rootView = AnyView(content())
        view.isShown = isShown
    }

    static func dismantleNSView(_ view: StatusBarAccessoryAnchorView, coordinator: ()) {
        view.detach()
    }
}

@available(macOS 26, *)
final class StatusBarAccessoryAnchorView: NSView {
    let accessory = StatusBarAccessoryController()
    var onAttachmentChange: ((Bool) -> Void)?
    private weak var splitViewItem: NSSplitViewItem?

    var isShown = true {
        didSet {
            guard isShown != oldValue else { return }
            applyVisibility(animated: true)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            detach()
        } else {
            // The split view hierarchy around a new detail view can still be settling.
            DispatchQueue.main.async { [weak self] in
                self?.attachIfNeeded()
            }
        }
    }

    private func attachIfNeeded() {
        guard splitViewItem == nil, window != nil else { return }
        guard let item = Self.splitViewItem(containing: self) else {
            onAttachmentChange?(false)
            return
        }
        item.addBottomAlignedAccessoryViewController(accessory)
        splitViewItem = item
        applyVisibility(animated: false)
        onAttachmentChange?(true)
    }

    func detach() {
        defer { splitViewItem = nil }
        guard let item = splitViewItem,
              let index = item.bottomAlignedAccessoryViewControllers.firstIndex(of: accessory) else { return }
        item.removeBottomAlignedAccessoryViewController(at: index)
    }

    private func applyVisibility(animated: Bool) {
        guard splitViewItem != nil else { return }
        if animated && !Motion.reduceMotion {
            accessory.animator().isHidden = !isShown
        } else {
            accessory.isHidden = !isShown
        }
    }

    /// The split view item whose view contains `view`, found through the enclosing
    /// `NSSplitView`'s controller. The split view wraps each item's view, so the test is on
    /// `view` itself, not on the split view's direct child.
    private static func splitViewItem(containing view: NSView) -> NSSplitViewItem? {
        var current: NSView? = view
        while let candidate = current {
            if let splitView = candidate.superview as? NSSplitView,
               let controller = splitView.delegate as? NSSplitViewController {
                return controller.splitViewItems.first { item in
                    item.viewController.isViewLoaded && view.isDescendant(of: item.viewController.view)
                }
            }
            current = candidate.superview
        }
        return nil
    }
}

@available(macOS 26, *)
final class StatusBarAccessoryController: NSSplitViewItemAccessoryViewController {
    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    override func loadView() {
        view = hostingView
    }
}
