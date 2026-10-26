import CoreGraphics
import SwiftUI
import Testing
@testable import Pulse

extension PanelGlobalsSuite {
    /// The liquid join between a docked rail and its edge (`DropletTether`),
    /// behind Settings → Experimental → Liquid docking.
    @Suite("Droplet tether")
    struct DropletTetherTests {
        @Test("The drawn pull starts slow and meets the pointer, at its speed, at the break")
        func displayPullMeetsThePointer() {
            let b = DropletTether.breakDistance
            #expect(DropletTether.displayPull(for: 0) == 0)
            #expect(DropletTether.displayPull(for: -10) == 0)
            #expect(abs(DropletTether.displayPull(for: b) - b) < 0.001)
            // Behind the hand all the way, never ahead of it.
            for d in stride(from: CGFloat(1), to: b, by: 1) {
                #expect(DropletTether.displayPull(for: d) < d)
            }
            // At the grip's share of the hand's speed off the edge, and at the
            // hand's own by the break: no jump in speed as it lets go.
            let start = DropletTether.displayPull(for: 0.01) / 0.01
            let end = (DropletTether.displayPull(for: b) - DropletTether.displayPull(for: b - 0.01)) / 0.01
            #expect(abs(start - DropletTether.grip) < 0.01)
            #expect(abs(end - 1) < 0.01)
        }

        @Test("A fluid turn leaves along one line and arrives along the other")
        func fluidTurnIsTangentAtBothEnds() {
            for ramp in [CGFloat(0), DropletTether.flareRamp, 1] {
                let points = DropletTether.fluidTurn(
                    from: CGPoint(x: 0, y: 10), along: CGVector(dx: 1, dy: 0),
                    to: CGPoint(x: 20, y: 0), then: CGVector(dx: 0, dy: -1), ramp: ramp
                )
                #expect(points.last == CGPoint(x: 20, y: 0))
                // First step runs along x, last along y.
                #expect(abs(points[0].y - 10) < abs(points[0].x - 0) * 0.2)
                let last = points[points.count - 1], before = points[points.count - 2]
                #expect(abs(last.x - before.x) < abs(last.y - before.y) * 0.2)
            }
        }

        @MainActor
        @Test("Unpulled, the docked outline is the berth's own; pulled, it stays on the edge")
        func pullKeepsTheEdge() {
            let rail = DockLayout.size(for: 3, on: .vertical)
            let rect = CGRect(origin: .zero, size: rail)
            let rest = DockBerthShape(edge: .right).path(in: rect).boundingRect
            #expect(abs(rest.maxX - rect.maxX) < 0.01)
            for pull in [CGFloat(5), 30, 60, 79] {
                let bounds = DockBerthShape(edge: .right, pull: pull).path(in: rect).boundingRect
                // Still joined to the edge, and drawn `pull` into the panel.
                #expect(abs(bounds.maxX - rect.maxX) < 0.5, "pull \(pull)")
                #expect(abs(bounds.minX - (rect.minX - pull)) < 0.5, "pull \(pull)")
            }
        }

        @MainActor
        @Test("Once parted and drawn back, nothing is left on the edge")
        func partedNeckDrawsBack() {
            let rail = DockLayout.size(for: 3, on: .vertical)
            let rect = CGRect(origin: .zero, size: rail)
            let pull: CGFloat = 95
            let gone = DockBerthShape(edge: .right, pull: pull, parted: 1).path(in: rect)
            // The body ends `pull` short of the edge; at most a hairline remains.
            #expect(gone.boundingRect.maxX < rect.maxX - pull + rail.width * 0.05 + 1)
            let parting = DockBerthShape(edge: .right, pull: pull, parted: 0.3).path(in: rect)
            #expect(parting.boundingRect.maxX > rect.maxX - 1)
        }
    }
}
