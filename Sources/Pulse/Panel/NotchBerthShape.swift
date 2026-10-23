// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// An extension of the camera housing, flush with the physical screen top.
/// The rings keep their layout below the housing; only the surface grows.
///
/// Drawn like the top rail it replaces: the body's sides sweep **out** into
/// the screen's top edge through a concave fillet, so the surface reads as
/// growing out of the edge rather than as a slab parked against it. Without
/// the fillet the two top corners are square, which is the one thing the
/// docked rail has never looked like. [`DockBerthShape`](UsageDockView.swift)
/// draws the same curve for a rail that is not on a notch.
struct NotchBerthShape: Shape {
    var notchSize: CGSize
    var openness: CGFloat = 1

    /// Pulls each fillet's control points off its endpoints, the same 0.55
    /// circular-arc approximation `DockBerthShape` uses, so the two curves
    /// differ in size only, not in kind.
    private static let fillet: CGFloat = 0.55

    /// How far each fillet sweeps along and down from the screen's top edge:
    /// the housing's own fillet, so the surface continues the notch rather
    /// than meeting it with a bigger curve beside a smaller one. Apple
    /// publishes no figure. Notch apps use 6pt (boring.notch, after
    /// DynamicNotchKit), which beside the housing on a 14-inch MacBook Pro
    /// read a touch less round than the housing's own; 8 and 10 read rounder.
    /// 6.5 was picked by eye against the hardware. Fixed rather
    /// than scaled with `PanelMetrics` — it matches hardware, which does not
    /// change size with the panel. The rail elsewhere keeps
    /// `DockLayout.flareWidth` / `flareHeight`.
    static var filletRadius: CGFloat { 6.5 }

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    /// `rect` is the body **plus** `DockLayout.flareWidth` on each side, which
    /// is the room the fillets sweep into. The caller sizes the frame for it;
    /// `PanelHitArea.notchSurface` stays the body alone, so the grab area
    /// never claims more than the rail draws.
    func path(in rect: CGRect) -> Path {
        let progress = min(max(openness, 0), 1)
        guard progress > 0 else { return Path() }

        let flareWidth = Self.filletRadius * progress
        let flareHeight = min(Self.filletRadius * progress, rect.height)
        // The frame still leaves `DockLayout.flareWidth` either side; the
        // smaller fillet simply does not use all of it.
        let body = rect.insetBy(dx: DockLayout.flareWidth, dy: 0)

        let width = notchSize.width + (body.width - notchSize.width) * progress
        let height = notchSize.height + (body.height - notchSize.height) * progress
        let minX = rect.midX - width / 2
        let maxX = rect.midX + width / 2
        let top = rect.minY
        let bottom = top + height

        // The bottom corners cannot take more than the surface has left below
        // the fillets, or the two curves cross and the outline folds.
        let radius = min(DockLayout.cornerRadius, width / 2, max(height - flareHeight, 0))
        let k = Self.fillet

        var path = Path()

        // Along the screen's top edge, left to right, past where the left
        // fillet leaves it.
        path.move(to: CGPoint(x: minX - flareWidth, y: top))

        // Down into the body's left edge. Horizontal where it leaves the
        // screen edge, vertical where it meets the body, so both joins are
        // tangent-continuous.
        path.addCurve(
            to: CGPoint(x: minX, y: top + flareHeight),
            control1: CGPoint(x: minX - flareWidth * (1 - k), y: top),
            control2: CGPoint(x: minX, y: top + flareHeight * (1 - k))
        )

        path.addLine(to: CGPoint(x: minX, y: bottom - radius))
        path.addArc(
            tangent1End: CGPoint(x: minX, y: bottom),
            tangent2End: CGPoint(x: maxX, y: bottom),
            radius: radius
        )
        path.addLine(to: CGPoint(x: maxX - radius, y: bottom))
        path.addArc(
            tangent1End: CGPoint(x: maxX, y: bottom),
            tangent2End: CGPoint(x: maxX, y: top),
            radius: radius
        )

        path.addLine(to: CGPoint(x: maxX, y: top + flareHeight))

        // The mirrored fillet back out to the screen edge.
        path.addCurve(
            to: CGPoint(x: maxX + flareWidth, y: top),
            control1: CGPoint(x: maxX, y: top + flareHeight * (1 - k)),
            control2: CGPoint(x: maxX + flareWidth * (1 - k), y: top)
        )

        path.closeSubpath()
        return path
    }
}
