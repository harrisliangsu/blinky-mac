// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import CoreGraphics

/// Which display the panel is on, and how to name one so it can be found again.
///
/// **A display's `CGDirectDisplayID` is not an identity.** It is handed out
/// afresh when a screen is attached, so it changes between sessions, when a
/// monitor is unplugged and plugged back in, and when a laptop is docked. Its
/// UUID does not — that is the same physical display every time — so that is
/// what gets stored.
enum PanelScreen {
    /// The camera housing, in AppKit's global screen coordinates. The safe
    /// inset alone is a height, not evidence of the housing's width.
    static func notch(of screen: NSScreen) -> CGRect? {
        notch(in: screen.frame, topInset: screen.safeAreaInsets.top,
              left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
    }

    /// **Centred on the display, not on the gap.** The housing is in the
    /// middle of the panel, but the two menu-bar areas are not always the
    /// same width: on a 14-inch MacBook Pro at 1800pt they are 791 and 788,
    /// so the gap's centre sits 1.5pt right of the housing's, and the rail
    /// showed a sliver beside the housing's right edge. Photographed with the
    /// surface painted red, the left edge was flush and the right one stood
    /// out. The gap's width is kept; only where it sits comes from the frame.
    static func notch(in frame: CGRect, topInset: CGFloat, left: CGRect?, right: CGRect?) -> CGRect? {
        guard topInset > 0, let left, let right,
              left.width > 0, right.width > 0, right.minX > left.maxX
        else { return nil }
        let width = right.minX - left.maxX
        return CGRect(x: frame.midX - width / 2, y: frame.maxY - topInset,
                      width: width, height: topInset)
    }

    /// A name for this display that survives a reboot and a reconnection.
    static func identifier(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
        else { return nil }

        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))
        else { return nil }

        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    /// The display that name refers to, or nil if it isn't attached right now.
    ///
    /// Nil is the ordinary answer, not an error: people unplug monitors. The
    /// caller falls back to a screen that exists rather than leaving the panel
    /// parked in a space nobody can see.
    static func screen(withIdentifier identifier: String?) -> NSScreen? {
        guard let identifier else { return nil }
        return NSScreen.screens.first { self.identifier(of: $0) == identifier }
    }

    /// The display a point is on.
    ///
    /// `frame`, not `visibleFrame` — the menu bar and the Dock are part of a
    /// screen for the purpose of "which one is the pointer over", and a
    /// pointer up in the menu bar must not read as being on no screen at all.
    static func containing(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
