// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// A titled group of settings rows, drawn as one rounded card.
///
/// This is the shape the whole settings window is built from: a small caption
/// above a card, and inside the card a stack of rows divided by hairlines.
struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(.background)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
                    // Decoration must not sit above the chart's hover target.
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The settings window's row. The Token window's speed list uses
/// `SpendSpeedLayout` instead, through `SettingsRowDensity.compact`.
enum SettingsRowMetrics {
    static let verticalPadding: CGFloat = 11
    static let minimumHeight: CGFloat = 44
    static let titlePointSize: CGFloat = 13
    static let subtitlePointSize: CGFloat = 11
    static let labelSpacing: CGFloat = 3
    static let horizontalPadding: CGFloat = 14
}

/// `.regular` is every settings row. `.compact` is the output-speed list.
enum SettingsRowDensity: Equatable {
    case regular
    case compact

    var verticalPadding: CGFloat {
        switch self {
        case .regular: SettingsRowMetrics.verticalPadding
        case .compact: SpendSpeedLayout.verticalPadding
        }
    }

    var minimumHeight: CGFloat {
        switch self {
        case .regular: SettingsRowMetrics.minimumHeight
        case .compact: SpendSpeedLayout.minimumHeight
        }
    }

    var titlePointSize: CGFloat {
        switch self {
        case .regular: SettingsRowMetrics.titlePointSize
        case .compact: SpendSpeedLayout.titlePointSize
        }
    }

    var subtitlePointSize: CGFloat {
        switch self {
        case .regular: SettingsRowMetrics.subtitlePointSize
        case .compact: SpendSpeedLayout.subtitlePointSize
        }
    }

    var labelSpacing: CGFloat {
        switch self {
        case .regular: SettingsRowMetrics.labelSpacing
        case .compact: SpendSpeedLayout.labelSpacing
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular: SettingsRowMetrics.horizontalPadding
        case .compact: SpendSpeedLayout.horizontalPadding
        }
    }
}

/// One line inside a `SettingsGroup`: a label on the left, its control on the
/// right, and an optional explanation underneath the label — or, with
/// `controlBelow`, the control under the label, for a control too wide to
/// leave the label room beside it.
struct SettingsRow<Control: View>: View {
    let title: String
    let subtitle: String?
    /// A mark before the title, named by its SVG in `Resources`. Used where
    /// the row *is* the thing the mark stands for — reordering the rail, say,
    /// where the icons are what is being arranged, or a spend row naming the
    /// client that produced it.
    ///
    /// A resource name rather than a `Provider` because the spend pane draws
    /// clients that are not providers at all; see `SpendAgent.iconResource`.
    let icon: String?
    let controlBelow: Bool
    /// A row that belongs to the switch or menu above it. The extra inset is
    /// the only difference: the control is the same one, editing the same
    /// setting. Callers omit the row entirely while its parent is off.
    let nested: Bool
    let density: SettingsRowDensity
    @ViewBuilder let control: Control

    init(
        _ title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        controlBelow: Bool = false,
        nested: Bool = false,
        density: SettingsRowDensity = .regular,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.controlBelow = controlBelow
        self.nested = nested
        self.density = density
        self.control = control()
    }

    var body: some View {
        Group {
            if controlBelow {
                VStack(alignment: .leading, spacing: 9) {
                    label
                    control
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    label
                    Spacer(minLength: 0)
                    control
                }
            }
        }
        .padding(.horizontal, density.horizontalPadding)
        .padding(.leading, nested ? 22 : 0)
        .padding(.vertical, density.verticalPadding)
        .frame(minHeight: density.minimumHeight)
    }

    private var label: some View {
        HStack(alignment: .center, spacing: 16) {
            if let icon {
                LobeIconView(resource: icon, size: 15)
            }

            VStack(alignment: .leading, spacing: density.labelSpacing) {
                Text(title)
                    .font(.system(size: density.titlePointSize))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: density.subtitlePointSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

enum SettingsLayout {
    /// A ceiling for the controls on the right of a row, not a fixed size.
    ///
    /// A macOS `Picker` sizes itself to its longest option and cannot be made
    /// to fill a frame, so this caps how wide one may get — a menu holding
    /// "Weekly limit · GPT-5.3-Codex-Spark" truncates instead of towering over
    /// its neighbours, and the full text is still there when it opens. Pair it
    /// with `alignment: .trailing`: a `Picker` centres itself in whatever
    /// frame it's given, which would leave it short of the row's edge while a
    /// plain `Button` reaches it.
    static let controlWidth: CGFloat = 180
}

/// Hairline between rows. Inset to match the rows' own padding, the way
/// macOS's grouped lists do it.
struct SettingsRowDivider: View {
    var leadingInset: CGFloat = SettingsRowMetrics.horizontalPadding

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
    }
}
