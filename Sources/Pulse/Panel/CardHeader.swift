// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit

/// The three controls on the usage card's header, in the order they are drawn.
///
/// Token spend is present only while that reading is on. Open and Quit are
/// the pair that used to be a gear and a power symbol. Open is the filled
/// grid `square.grid.2x2.fill`: it opens the main window on the pane last
/// shown, not a settings sheet, and Blinky's own icon is not a control.
enum CardHeaderControl: String, CaseIterable, Equatable, Sendable {
    case tokenSpend
    case openApp
    case quit

    var symbolName: String {
        switch self {
        case .tokenSpend: "chart.bar"
        case .openApp: "square.grid.2x2.fill"
        case .quit: "power"
        }
    }
}

/// How the header spends its width.
///
/// The icon buttons used to take a 16pt pad each and the row's own gap, so
/// "Codex 用量" was drawn as "Cod…" with empty space before the icons.
enum CardHeaderMetrics {
    /// Extra points on each side of the glyph. The hover scale still fits.
    static let hitOutset: CGFloat = 4
    /// Space between the icon buttons. They sit as one cluster.
    static let clusterSpacing: CGFloat = 2
}

/// The title stays on one line. Wrapping would make the card taller than the
/// window budgeted, and the card is sliced at that edge. The type shrinks
/// before it is clipped. A name that still does not fit gets a tooltip.
enum HeaderTitleFit {
    static let minimumScale: CGFloat = 0.78

    static func needsTooltip(idealWidth: CGFloat, availableWidth: CGFloat) -> Bool {
        guard idealWidth > 1, availableWidth > 1 else { return false }
        return idealWidth * minimumScale > availableWidth + 0.5
    }
}

/// Which header control contains a point, in the window's base coordinates.
enum CardHeaderHit {
    /// The frames a button laid out. A null, infinite, or not-yet-laid-out
    /// rect is not a target. When two overlap, the smaller one wins, so a
    /// control sitting inside another's box is the one that was aimed at.
    static func control(
        at point: CGPoint,
        frames: [CardHeaderControl: CGRect]
    ) -> CardHeaderControl? {
        let hits = CardHeaderControl.allCases.filter { control in
            guard let frame = frames[control] else { return false }
            guard frame.width > 1, frame.height > 1, !frame.isNull, !frame.isInfinite else { return false }
            return frame.contains(point)
        }
        return hits.min { lhs, rhs in
            let left = frames[lhs] ?? .null
            let right = frames[rhs] ?? .null
            let areaL = left.width * left.height
            let areaR = right.width * right.height
            if areaL != areaR { return areaL < areaR }
            return lhs.rawValue < rhs.rawValue
        }
    }
}

/// The rectangles the header buttons report. A class so the card can write
/// them without holding the panel, and the panel can read them on the press.
final class HeaderFrameSink {
    var frames: [CardHeaderControl: CGRect] = [:]

    func note(_ control: CardHeaderControl, _ rect: CGRect) {
        if rect.width > 1, rect.height > 1, !rect.isNull, !rect.isInfinite {
            frames[control] = rect
        } else {
            frames[control] = nil
        }
    }

    /// Replaces every stored rect. A control that is not in `frames` is gone,
    /// so a button that has left the card is not a hit target.
    func replace(with frames: [CardHeaderControl: CGRect]) {
        var next: [CardHeaderControl: CGRect] = [:]
        for (control, rect) in frames {
            if rect.width > 1, rect.height > 1, !rect.isNull, !rect.isInfinite {
                next[control] = rect
            }
        }
        self.frames = next
    }
}

/// Header rectangles read from the views that are in the window now.
///
/// The probes also report as they lay out. That report can still be missing
/// on the first click after launch, so the press asks the views directly and
/// does not wait for the callback.
@MainActor
enum HeaderControlFrames {
    static func collect(in root: NSView?) -> [CardHeaderControl: CGRect] {
        guard let root else { return [:] }
        var frames: [CardHeaderControl: CGRect] = [:]
        /// `preferred` is the probe the button laid out. The hand sits on the
        /// same control and can be a different rectangle; it fills in only
        /// when the probe has not reported.
        func consider(_ control: CardHeaderControl?, _ view: NSView, preferred: Bool) {
            guard let control, view.window != nil else { return }
            let rect = view.convert(view.bounds, to: nil)
            guard rect.width > 1, rect.height > 1, !rect.isNull, !rect.isInfinite else { return }
            if frames[control] == nil || preferred {
                frames[control] = rect
            }
        }
        func walk(_ view: NSView) {
            if let probe = view as? ControlFrameProbe.ProbeView,
               let control = CardHeaderControl(rawValue: probe.marker) {
                consider(control, view, preferred: true)
            }
            if let hand = view as? PointerHand.HandView {
                consider(hand.headerControl, view, preferred: false)
            }
            for child in view.subviews { walk(child) }
        }
        walk(root)
        return frames
    }

    /// The header control whose view contains `point`, in window coordinates.
    /// The probe wins over the hand when both contain it, because the probe is
    /// the rectangle the button laid out.
    static func control(at point: CGPoint, in root: NSView?) -> CardHeaderControl? {
        guard let root else { return nil }
        var found: (CardHeaderControl, CGFloat, Bool)?
        func consider(_ control: CardHeaderControl?, _ view: NSView, preferred: Bool) {
            guard let control, view.window != nil else { return }
            let rect = view.convert(view.bounds, to: nil)
            guard rect.width > 1, rect.height > 1, !rect.isNull, !rect.isInfinite else { return }
            guard rect.contains(point) else { return }
            let area = rect.width * rect.height
            if let current = found {
                if preferred && !current.2 { found = (control, area, true); return }
                if current.2 && !preferred { return }
                if area < current.1 { found = (control, area, preferred) }
            } else {
                found = (control, area, preferred)
            }
        }
        func walk(_ view: NSView) {
            if let probe = view as? ControlFrameProbe.ProbeView,
               let control = CardHeaderControl(rawValue: probe.marker) {
                consider(control, view, preferred: true)
            }
            if let hand = view as? PointerHand.HandView {
                consider(hand.headerControl, view, preferred: false)
            }
            for child in view.subviews { walk(child) }
        }
        walk(root)
        return found?.0
    }
}

/// What `FloatingPanel.sendEvent` does with a mouse event before the rail's
/// drag sees it.
///
/// The panel never becomes key, and a SwiftUI control under it is not a
/// reliable place for the press: the symbol's own view, or a frame reporter
/// that still hit-tests, takes the point and does nothing with it. The
/// window already owns ring clicks for that reason. Header clicks are the
/// same class. The button reports the rectangle it laid out; this decides
/// from that rectangle. `pass` leaves the event for the rail.
enum HeaderClickDispatch {
    enum Outcome: Equatable {
        /// Not a header press.
        case pass
        /// The panel keeps the event. A drag does not start.
        case taken
        /// Mouse-up is still inside the control that was pressed.
        case activate(CardHeaderControl)
    }

    static func outcome(
        type: NSEvent.EventType,
        point: CGPoint,
        frames: [CardHeaderControl: CGRect],
        pressed: inout CardHeaderControl?
    ) -> Outcome {
        switch type {
        case .leftMouseDown:
            guard let control = CardHeaderHit.control(at: point, frames: frames) else { return .pass }
            pressed = control
            return .taken
        case .leftMouseDragged:
            guard pressed != nil else { return .pass }
            return .taken
        case .leftMouseUp:
            guard let pressedControl = pressed else { return .pass }
            pressed = nil
            if CardHeaderHit.control(at: point, frames: frames) == pressedControl {
                return .activate(pressedControl)
            }
            return .taken
        default:
            return .pass
        }
    }
}
