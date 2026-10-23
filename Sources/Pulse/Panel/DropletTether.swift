// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The liquid join between a docked rail and the edge it is being pulled off,
/// or is being drawn onto.
///
/// **Pulled off, the rail does not let go at once.** It lags the pointer
/// (`displayPull`), and what joins it to the edge stretches from the berth's
/// ordinary flare into a neck that thins until it pinches at
/// `breakDistance`; only then does the rail stand free. Drawn on, the neck
/// forms thin and thickens as the follow spring carries the rail onto the
/// edge (`FloatingPanel.step`). Released short of the break, the same spring
/// carries it back.
///
/// **One outline, two pieces.** The body is the rail's own rectangle, moved
/// off the edge by the pull; the bridge is everything between it and the
/// edge. Each shape builds its own body (the corners are its own style) and
/// takes the bridge from here, and the two are unioned, so the outline is
/// one clean path for the fill, the light panel's hairline and the glass.
///
/// Drawn **once, facing right** — the edge is the vertical line `x = gap +
/// bodyWidth`, the body's edge side is `x = bodyWidth` — and turned into
/// place by the shape, as `DockBerthShape` already does.
enum DropletTether {
    /// How far the pointer carries a docked rail off its edge before the neck
    /// pinches and the rail stands free. Where the rail is drawn reaches the
    /// same distance at the same moment (`displayPull`), so letting go is not
    /// a jump.
    static var breakDistance: CGFloat { 80 }

    /// Where the rail is drawn for a pull of `distance`: behind the pointer at
    /// first, catching up by the break.
    ///
    /// It moves at `grip` of the hand's speed off the edge and at the hand's
    /// own speed by the break, where it reaches the pointer — so the moment
    /// it lets go is neither a jump in place nor in speed. The first version
    /// was `d² / break`, which arrived at twice the hand's speed and threw
    /// the rail at the pointer as it let go. Grip as in codenotch's notch
    /// magnet (15%).
    static func displayPull(for distance: CGFloat) -> CGFloat {
        let d = min(max(distance, 0), breakDistance)
        let rest = 1 - d / breakDistance
        return d * (1 - (1 - grip) * rest * rest)
    }

    /// How much of the hand's movement a rail held on its edge follows at
    /// first.
    static let grip: CGFloat = 0.15

    /// How long the two pieces of a parted neck take to draw back. The window
    /// stays where the dock put it for that long, so they can be drawn.
    static let partingDuration: CFTimeInterval = 0.22

    /// How thin a neck starts when the rail is drawn onto an edge (0 is full
    /// contact, 1 pinched).
    static let attachThinning: CGFloat = 0.85

    struct Profile {
        /// The body's thickness: its edge side is at this `x`.
        var bodyWidth: CGFloat
        /// From the body's edge side to the edge.
        var gap: CGFloat
        /// The pull alone, which is what thins the neck. The gap can be more
        /// (at a notch it includes the housing).
        var pull: CGFloat
        /// The middle of the run along the edge.
        var centre: CGFloat
        /// Half the contact along the edge before anything is pulled: the
        /// body's half length, inside the flares.
        var contact: CGFloat
        /// How far the flare reaches along the edge past the contact.
        var flareAlong: CGFloat
        /// How far the flare reaches in from the edge.
        var flareIn: CGFloat
        /// What part of `flareIn` it gives up as the rail is pulled.
        var flareGives: CGFloat = 0.5
        /// What part of `flareAlong` it gives up as the neck narrows.
        var flareShrinks: CGFloat = 0.5
        /// Half the neck where it meets the body, once it has narrowed.
        var joinHalf: CGFloat
        /// Half the neck where it meets the edge, once it has narrowed.
        var footHalf: CGFloat
        /// How far from the edge the waist must be at least: at a notch, the
        /// housing, which hides anything drawn behind it.
        var waistClearance: CGFloat = 0
        /// Extra thinning on top of what the pull gives, for a rail being
        /// drawn onto the edge.
        var thinning: CGFloat = 0
        /// One sweep from the waist into the edge. Off at a notch, where the
        /// foot keeps the housing's width and fillet.
        var mergesFoot: Bool = true
        /// After the neck has parted: how far its two pieces have drawn back
        /// into the body and the edge, 0 to 1.
        var parted: CGFloat = 0
    }

    struct Bridge {
        var path: Path
        /// Half the neck where it meets the body; the body's corners on that
        /// side may round off only outside it.
        var joinHalf: CGFloat
    }

    static func bridge(_ profile: Profile) -> Bridge {
        let w = profile.bodyWidth
        let x = w + max(profile.gap, 0)
        let cy = profile.centre
        let k: CGFloat = 0.55

        let fullIn = max(profile.flareIn, 0.001)
        let flareIn = fullIn * (1 - profile.flareGives * min(max(profile.pull, 0) / fullIn, 1))
        let footX = x - flareIn

        // The neck starts once the flare has drawn clear of the body; before
        // that the rail simply stretches, the flare sliding with the edge.
        let start = (fullIn - (x - w - max(profile.pull, 0))) / (1 + profile.flareGives)
        let neck = footX > w
        let fromPull = neck
            ? min(max((profile.pull - max(start, 0)) / max(breakDistance - max(start, 0), 1), 0), 1)
            : 0
        let parted = neck ? min(max(profile.parted, 0), 1) : 0
        let u = parted > 0 ? 1 : neck ? max(fromPull, min(max(profile.thinning, 0), 1)) : 0
        let eased = smoothstep(u / 0.5)
        // In the last stretch the foot draws back a little into the edge, so
        // what is left there at the break is small. The join keeps its
        // width: drawn back too, the neck read as a stick, not a drop.
        let parting = profile.mergesFoot ? 1 - 0.5 * smoothstep((u - 0.75) / 0.25) : 1

        let joinHalf = lerp(profile.contact, min(profile.joinHalf, profile.contact), eased)
        let footHalf = lerp(profile.contact, min(profile.footHalf, profile.contact), eased) * parting
        let along = profile.flareAlong * (1 - profile.flareShrinks * eased) * parting

        // The top half as points, from where it leaves the body out to the
        // edge; the bottom half is its mirror, walked back.
        var top: [CGPoint] = []
        var waistIndex: Int?
        let footY = cy - footHalf
        let edge = CGPoint(x: x, y: footY - along)
        if neck {
            // Holds its thickness most of the way, then gives quickly, the way a
            // drop lets go.
            let waistHalf = min(joinHalf, footHalf) * (1 - pow(u, 2.2))
            let limit = x - profile.waistClearance
            let middle = limit > w ? min((w + footX) / 2, (w + limit) / 2) : (w + x) / 2
            let join = CGPoint(x: w, y: cy - joinHalf)
            top.append(join)
            if profile.mergesFoot {
                // Two turns and nothing between: off the body's side into
                // the waist, and from the waist into the edge. The waist
                // starts where the flare did, so the first frame of the neck
                // is the flare it grew out of.
                let waist = CGPoint(x: lerp(footX, middle, eased), y: cy - waistHalf)
                // Round turns for the neck: a ramped one bunches its turning
                // in the middle, and on a long thin neck that reads as a
                // corner. The sweep into the edge starts as the flare it
                // grew out of and rounds as the neck forms.
                top += fluidTurn(from: join, along: CGVector(dx: 0, dy: 1), to: waist, then: CGVector(dx: 1, dy: 0), ramp: 0)
                waistIndex = top.count - 1
                top += fluidTurn(from: waist, along: CGVector(dx: 1, dy: 0), to: edge, then: CGVector(dx: 0, dy: -1),
                                 ramp: flareRamp * (1 - eased))
            } else {
                // Narrows to the waist, widens to the foot, then the edge's
                // own fillet: at a notch the foot is the housing, and the
                // fillet beside it has to stay the housing's.
                let waist = CGPoint(x: middle, y: cy - waistHalf)
                let foot = CGPoint(x: footX, y: footY)
                top += cubic(join, CGPoint(x: w, y: join.y + (waist.y - join.y) * 0.6),
                             CGPoint(x: middle - (middle - w) * 0.6, y: waist.y), waist)
                waistIndex = top.count - 1
                top += cubic(waist, CGPoint(x: middle + (footX - middle) * 0.6, y: waist.y),
                             CGPoint(x: footX - (footX - middle) * 0.6, y: footY), foot)
                top += cubic(foot, CGPoint(x: x - flareIn * (1 - k), y: footY),
                             CGPoint(x: x, y: edge.y + (footY - edge.y) * k), edge)
            }
        } else {
            // The flare into the edge, as the berth draws it.
            let foot = CGPoint(x: footX, y: footY)
            top.append(foot)
            top += fluidTurn(from: foot, along: CGVector(dx: 1, dy: 0), to: edge, then: CGVector(dx: 0, dy: -1), ramp: flareRamp)
        }

        func mirrored(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: 2 * cy - point.y) }

        var path = Path()
        if parted > 0, let waistIndex {
            // **Let go:** two pieces, each drawing back into what it came out
            // of — the half on the body into the body, the foot into the
            // edge — instead of vanishing on the frame the neck parts.
            let left = 1 - parted
            let onBody = top[...waistIndex].map { CGPoint(x: w + ($0.x - w) * left, y: $0.y) }
            let onEdge = top[waistIndex...].map { CGPoint(x: x - (x - $0.x) * left, y: $0.y) }
            path.addLines(onBody + onBody.reversed().map(mirrored))
            path.addLine(to: CGPoint(x: w - 1, y: mirrored(onBody[0]).y))
            path.addLine(to: CGPoint(x: w - 1, y: onBody[0].y))
            path.closeSubpath()
            path.addLines(onEdge + onEdge.reversed().map(mirrored))
            path.closeSubpath()
            return Bridge(path: path, joinHalf: joinHalf)
        }
        path.addLines(top + top.reversed().map(mirrored))
        // Back through the body, a point inside it, so the union closes
        // without a hairline at the join.
        let begin = top[0]
        path.addLine(to: CGPoint(x: begin.x - 1, y: mirrored(begin).y))
        path.addLine(to: CGPoint(x: begin.x - 1, y: begin.y))
        path.closeSubpath()

        return Bridge(path: path, joinHalf: neck ? joinHalf : profile.contact)
    }

    // MARK: - Curves

    /// How much of a flare's turn is eased in and out (`fluidTurn`): half,
    /// as codenotch has it. All of it bunches the turning into the middle and
    /// reads as a corner again; none is a circular arc.
    static let flareRamp: CGFloat = 0.5

    /// A quarter turn whose curvature can rise from nothing and fall back to
    /// nothing, so it leaves one straight line and joins the next without a
    /// visible start or end. The idea is codenotch's "fluid turn"; this
    /// curve is our own: the heading runs from 0 to π/2 as a mix of a
    /// straight ramp (a circular arc) and half a cosine (curvature zero at
    /// both ends), `ramp` of the latter; the unit curve is that heading
    /// integrated, then scaled to the box between the two points.
    ///
    /// `along` is the direction it leaves `from`, `then` the one it arrives
    /// at `to` with; both axis-aligned, at right angles. Returns the points
    /// after `from`, ending at `to`.
    static func fluidTurn(
        from: CGPoint, along: CGVector, to: CGPoint, then: CGVector, ramp: CGFloat = flareRamp
    ) -> [CGPoint] {
        let dx = to.x - from.x, dy = to.y - from.y
        let first = dx * along.dx + dy * along.dy
        let second = dx * then.dx + dy * then.dy
        return unitTurn(ramp: ramp).dropFirst().map { point in
            CGPoint(
                x: from.x + along.dx * point.x * first + then.dx * point.y * second,
                y: from.y + along.dy * point.x * first + then.dy * point.y * second
            )
        }
    }

    /// The turn from (0, 0) heading along x to (1, 1) heading along y.
    private static func unitTurn(ramp: CGFloat) -> [CGPoint] {
        let steps = 32
        let mix = min(max(ramp, 0), 1)
        var raw: [CGPoint] = [.zero]
        var point = CGPoint.zero
        let ds = 1 / CGFloat(steps)
        for step in 0..<steps {
            // Midpoint rule, so the two ends come out symmetric.
            let s = (CGFloat(step) + 0.5) * ds
            let eased = (1 - cos(CGFloat.pi * s)) / 2
            let heading = CGFloat.pi / 2 * ((1 - mix) * s + mix * eased)
            point.x += cos(heading) * ds
            point.y += sin(heading) * ds
            raw.append(point)
        }
        let end = raw[raw.count - 1]
        return raw.map { CGPoint(x: $0.x / end.x, y: $0.y / end.y) }
    }

    /// A cubic as points after its start.
    private static func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> [CGPoint] {
        (1...24).map { step in
            let t = CGFloat(step) / 24, m = 1 - t
            let a = m * m * m, b = 3 * m * m * t, c = 3 * m * t * t, d = t * t * t
            return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                           y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private static func smoothstep(_ t: CGFloat) -> CGFloat {
        let c = min(max(t, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
