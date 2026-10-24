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
