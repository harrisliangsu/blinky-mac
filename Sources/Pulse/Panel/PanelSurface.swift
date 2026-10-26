// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What the panel's shapes are filled with: flat black, flat light, or Liquid
/// Glass.
///
/// Dark (flat black) is the default and stays it. The panel sits over
/// whatever the user is working on all day, and a solid surface is the one
/// that is legible over anything — glass takes on the colour and busyness of
/// whatever happens to be behind it, which is lovely over a photo and hard
/// work over a code editor. Light is the same solid idea in the other
/// direction: a black bar parked on a page of work is a hole in the page.
/// So both are offered rather than assumed.
///
/// The glass is dimmed (`PanelGlass.dim`, by the reader's transparency) and
/// the panel is drawn dark on it: white content over a light darkening. That
/// is Apple's guidance for the clear variant, which unlike `.regular` does not
/// manage its own legibility — it shows what is behind it almost untouched, so
/// white text disappears over a white page without the dim, and dark text
/// over a dark one without the white. Measured on 26.7: no dim, white on white
/// was invisible; 0.3 black was readable over white and barely visible over
/// black or a busy backdrop.
struct PanelSurface<S: Shape>: View {
    let shape: S
    let usesGlass: Bool
    /// Tints the surface when a limit is close enough to matter. Nil leaves it
    /// neutral.
    var tint: Color?
    /// The side lying against the screen's edge, if any: the light panel's
    /// hairline is left off it, where it would be a grey line along the very
    /// edge of the display.
    var screenEdge: Edge.Set = []
    /// The reader's setting, handed down from the panel's root.
    @Environment(\.glassTransparency) private var transparency
    /// Light only when the reader chose the light panel; the root pins it.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Deliberately hit-testable, and the panel cannot be dragged without
        // it. A window is only handed a press if something in it claims that
        // point, and this surface is the only thing covering the empty black
        // between the rings — the rings themselves claim their own area for
        // their tracking areas, which is why they went on working while the
        // gaps between them went dead the moment this was marked
        // `allowsHitTesting(false)`.
        //
        // Nothing is at risk in claiming it: the drag is taken by the window
        // itself in `FloatingPanel.sendEvent`, before any view sees the event,
        // so there is no handle here for this to steal a press from.
        surface
            // Claimed to the capsule's own outline rather than to its bounding
            // box, so the whole capsule can be taken hold of and the corners
            // it doesn't fill still let a click through to what is behind.
            .contentShape(shape)
    }

    @ViewBuilder
    private var surface: some View {
        if usesGlass {
            glass
        } else if colorScheme == .light {
            shape.fill(tint ?? PanelLight.fill)
                // Black over a black window loses its edge too, but light over
                // a white page is the usual case for this surface, and without
                // the line the card's tail is all that says where it ends.
                //
                // **Inside the outline, not outside.** The window is exactly
                // card + rail wide, so the rail's far side and the card's far
                // side lie on the window's edge, and the half of a line drawn
                // outside them was cut off — that side looked sliced (#74).
                // Outlined from the *normalized* path: the card's tail is its
                // own subpath overlapping the body, and stroking that as it
                // stands draws the body's edge straight through the join.
                .overlay {
                    let outline = PanelOutline(shape: shape)
                        .stroke(PanelLight.edge, lineWidth: PanelLight.edgeWidth * 2)
                        .clipShape(shape)
                    // Masked only where a side lies on the screen; the card and
                    // a free rail have none, and need no extra pass. **Only
                    // that side:** the mask reaches far past the frame on the
                    // others, because a rail pulled off its edge is drawn
                    // outside the frame (`DropletTether`), and a mask the size
                    // of the frame cut its hairline off there.
                    if screenEdge.isEmpty {
                        outline
                    } else {
                        outline.mask {
                            Rectangle()
                                .padding(screenEdge, PanelLight.edgeWidth)
                                .padding(Edge.Set.all.subtracting(screenEdge), -2000)
                        }
                    }
                }
        } else {
            shape.fill(tint ?? .black)
        }
    }



    /// `.clear`, not `.regular`. Measured over a bright, busy backdrop:
    /// `.regular` comes out an opaque milky white with nothing showing through
    /// — frosted glass, not Liquid Glass. AppKit's `NSGlassEffectView` was
    /// measured against this too and is pixel-for-pixel the same material, so
    /// the modifier wins: it takes the shape directly, which the open/close
    /// morph needs, where the AppKit view knows only a corner radius and would
    /// have to be clipped to the rail's flare.
    ///
    /// It needs macOS 26; the package deploys to 14, so older systems get the
    /// closest thing that has always existed — a vibrant blur. Not the same
    /// material, but the same idea, and it degrades rather than failing.
    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.clear.tint(tint ?? PanelGlass.dim(transparency: transparency)), in: shape)
                // The glass and its tint are composited by the system, not
                // drawn into this window, so where only glass lies the
                // window's own pixels are empty — and the window server sends
                // a press there to whatever is behind, before `sendEvent`
                // could take it. Reported on the docked rail (#68): rings
                // draggable, glass between them not. A fill no one can see
                // gives those pixels to the window.
                .background(shape.fill(PanelGlass.claim))
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay { tint.map { shape.fill($0.opacity(0.28)) } }
        }
    }
}

enum PanelGlass {
    /// The darkest the dimming goes, at transparency 0. Measured on 26.7:
    /// 0.3 was the least grey over a white page that still read, so the
    /// default sits there, in the middle of the slider.
    static let maximumDim = 0.6
    static let defaultTransparency = 0.5
    /// Under the glass only so the window owns the pixels and is handed the
    /// press. Not zero: a fully clear pixel is one the window server passes on.
    static let claim = Color.black.opacity(0.01)

    /// Laid under the panel's white content on clear glass. The alert tint
    /// replaces it on the sliver.
    static func dim(transparency: Double) -> Color {
        .black.opacity((1 - min(max(transparency, 0), 1)) * maximumDim)
    }

    /// Where the text starts to darken: the default, so nobody who left the
    /// slider alone sees anything change.
    static let inkTurns = 0.5
    /// Where the rest of the panel follows the text into the light scheme —
    /// hairlines, tracks and the deeper usage colours (`Color.pulse*`). Past
    /// here the text is darker than mid grey.
    static let schemeTurns = 0.75

    /// The text's colour on glass: white (the dark scheme's label colour) up
    /// to `inkTurns`, then darkening with the slider to black at its clearest
    /// end. Nil where the scheme's own label colour is the answer.
    ///
    /// **The reader asked for this, knowing the cost.** Clear glass takes on
    /// whatever is behind it; past the middle the panel is mostly the page
    /// under it, which is usually light, so white text vanished there. Black
    /// text vanishes over a dark window instead — Pulse cannot see what is
    /// behind the panel without recording the screen — and the slider's
    /// caption says so.
    static func ink(transparency: Double) -> Color? {
        let t = min(max(transparency, 0), 1)
        guard t > inkTurns else { return nil }
        let white = 1 - (t - inkTurns) / (1 - inkTurns)
        // At the opacity the label colour has, so the step off it is not seen.
        return Color(white: white, opacity: 0.85)
    }

    static func scheme(transparency: Double) -> ColorScheme {
        transparency > schemeTurns ? .light : .dark
    }
}

/// The light panel's surface (#74). Not pure white: on a white page that is
/// a hole with a hairline round it, and the slight grey reads as a surface.
enum PanelLight {
    static let fill = Color(white: 0.97)
    static let edge = Color.black.opacity(0.12)
    static var edgeWidth: CGFloat { 1 }
}

/// A shape's outline with its overlaps dissolved, so a stroke follows only
/// the outside of the union.
private struct PanelOutline<S: Shape>: Shape {
    let shape: S

    func path(in rect: CGRect) -> Path {
        shape.path(in: rect).normalized(eoFill: false)
    }
}

private struct GlassTransparencyKey: EnvironmentKey {
    static let defaultValue = PanelGlass.defaultTransparency
}

extension EnvironmentValues {
    var glassTransparency: Double {
        get { self[GlassTransparencyKey.self] }
        set { self[GlassTransparencyKey.self] = newValue }
    }
}
