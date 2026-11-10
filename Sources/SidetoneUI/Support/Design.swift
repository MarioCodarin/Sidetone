import SwiftUI
import AppKit
import SidetoneCore

/// The design system: every spacing, type, radius, colour and motion value the UI uses lives
/// here, so the look can be changed in one place.
///
/// Direction: a quiet studio instrument. Warm graphite surfaces, one amber "signal" accent for
/// arming a recording, red only while live. Spacing follows a 4 pt grid; type is one family
/// (SF) plus a monospaced figure style for the clock and levels.
enum DS {

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
    }

    /// SF Pro, one family. Weights stay 400–600; the clock is the only light face.
    enum Typo {
        static let wordmark = Font.system(size: 13, weight: .semibold)
        static let heading  = Font.system(size: 17, weight: .semibold)
        static let title    = Font.system(size: 13, weight: .medium)
        static let body     = Font.system(size: 12)
        static let caption  = Font.system(size: 11)
        static let section  = Font.system(size: 11, weight: .semibold)
        static let timer    = Font.system(size: 30, weight: .light, design: .monospaced).monospacedDigit()
        static let mono     = Font.system(size: 10, weight: .medium, design: .monospaced)
    }

    enum Palette {
        // Warm graphite ramp. Surfaces stay neutral; the accent carries the colour.
        static let canvas   = dynamic(light: 0xF7F4EE, dark: 0x141312)
        static let surface  = dynamic(light: 0xFFFFFF, dark: 0x1C1A18)
        static let raised   = dynamic(light: 0xEDE7DE, dark: 0x272320)
        static let hairline = dynamic(light: 0x1C1A17, dark: 0xFFFFFF, alpha: 0.10)
        static let hairlineStrong = dynamic(light: 0x1C1A17, dark: 0xFFFFFF, alpha: 0.18)

        static let textPrimary   = dynamic(light: 0x1C1A17, dark: 0xF4F0E9)
        static let textSecondary = dynamic(light: 0x6B645B, dark: 0xABA39A)
        static let textMuted     = dynamic(light: 0x938B81, dark: 0x7B746B)

        /// "Armed" / primary action. Amber is the one accent.
        static let accent   = dynamic(light: 0xA05A10, dark: 0xE9A23B)
        /// Text/icon on an accent fill.
        static let onAccent = dynamic(light: 0xFFFDF8, dark: 0x1A1714)
        /// Live recording only.
        static let record   = dynamic(light: 0xC92F35, dark: 0xF2555B)
        /// Needs attention: missing permission, unmixed take, paused.
        static let attention = dynamic(light: 0x9A5F17, dark: 0xE0A152)

        static let hover   = dynamic(light: 0x1C1A17, dark: 0xFFFFFF, alpha: 0.06)
        static let pressed = dynamic(light: 0x1C1A17, dark: 0xFFFFFF, alpha: 0.11)

        static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return hex(isDark ? dark : light, alpha: alpha)
            })
        }

        static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
            NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: alpha
            )
        }
    }

    enum Motion {
        /// Hover, press and focus feedback.
        static let quick = Animation.easeOut(duration: 0.14)
        /// Content appearing or disappearing.
        static let standard = Animation.easeInOut(duration: 0.22)
    }

    enum Size {
        static let panelWidth: CGFloat = 344
        static let settingsWidth: CGFloat = 460
        static let setupWidth: CGFloat = 500
        static let orbit: CGFloat = 76
        static let controlHeight: CGFloat = 32
    }
}

// MARK: - Hover state

/// Tracks pointer hover. `@State` cannot be used in this package (Command Line Tools lack the
/// SwiftUIMacros plugin that expands it), but the `State` type itself works as a plain property,
/// so every hover effect goes through here.
struct HoverReader<Content: View>: View {
    private let hovering = State(initialValue: false)
    let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(hovering.wrappedValue)
            .onHover { hovering.wrappedValue = $0 }
    }
}

// MARK: - Motion

extension View {
    /// Animates `value` changes unless the user asked for Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation = DS.Motion.standard, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Buttons

/// Filled, full-width action. Amber for the primary action; neutral for the secondary one.
struct ActionButtonStyle: ButtonStyle {
    enum Fill { case accent, neutral }
    var fill: Fill = .accent
    var height: CGFloat = DS.Size.controlHeight

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Content(configuration: configuration, fill: fill, height: height)
    }

    private struct Content: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let fill: Fill
        let height: CGFloat

        var body: some View {
            HoverReader { hovering in
                configuration.label
                    .font(DS.Typo.title)
                    .foregroundStyle(fill == .accent ? DS.Palette.onAccent : DS.Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .fill(background(hovering: hovering))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .strokeBorder(fill == .neutral ? DS.Palette.hairline : .clear, lineWidth: 1)
                    )
                    .scaleEffect(configuration.isPressed ? 0.99 : 1)
                    .opacity(isEnabled ? 1 : 0.4)
                    .animation(DS.Motion.quick, value: configuration.isPressed)
                    .animation(DS.Motion.quick, value: hovering)
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            }
        }

        private func background(hovering: Bool) -> AnyShapeStyle {
            switch fill {
            case .accent:
                return AnyShapeStyle(DS.Palette.accent.opacity(configuration.isPressed ? 0.85 : hovering ? 0.95 : 1))
            case .neutral:
                return AnyShapeStyle(configuration.isPressed ? DS.Palette.pressed
                                     : hovering ? DS.Palette.raised : DS.Palette.surface)
            }
        }
    }
}

/// A square icon-only button that shows its hit area on hover.
struct IconButtonStyle: ButtonStyle {
    var hoverTint: Color = DS.Palette.textPrimary
    var restTint: Color?
    var size: CGFloat = 26

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Content(configuration: configuration, hoverTint: hoverTint, restTint: restTint, size: size)
    }

    private struct Content: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let hoverTint: Color
        let restTint: Color?
        let size: CGFloat

        var body: some View {
            HoverReader { hovering in
                configuration.label
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hovering || configuration.isPressed
                                     ? AnyShapeStyle(hoverTint)
                                     : AnyShapeStyle(restTint ?? DS.Palette.textSecondary))
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                            .fill(configuration.isPressed ? DS.Palette.pressed : hovering ? DS.Palette.hover : .clear)
                    )
                    .opacity(isEnabled ? 1 : 0.4)
                    .animation(DS.Motion.quick, value: hovering)
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
            }
        }
    }
}

/// A text-and-icon button for quiet, low-priority actions.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HoverReader { hovering in
            configuration.label
                .font(DS.Typo.caption)
                .foregroundStyle(hovering || configuration.isPressed
                                 ? AnyShapeStyle(DS.Palette.textPrimary)
                                 : AnyShapeStyle(DS.Palette.textSecondary))
                .padding(.horizontal, DS.Space.s)
                .frame(minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(configuration.isPressed ? DS.Palette.pressed : hovering ? DS.Palette.hover : .clear)
                )
                .animation(DS.Motion.quick, value: hovering)
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
        }
    }
}

/// A quiet inline action: accent text that underlines on hover. Used where a filled button
/// would out-shout the thing it fixes.
struct TextActionButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HoverReader { hovering in
            configuration.label
                .font(DS.Typo.caption.weight(.medium))
                .foregroundStyle(DS.Palette.accent)
                .underline(hovering)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(DS.Motion.quick, value: hovering)
                .contentShape(Rectangle())
        }
    }
}

/// Makes a whole list row a button: hover fill, no chrome at rest.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(configuration.isPressed ? DS.Palette.pressed : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }
}

// MARK: - Rows, sections, details

extension View {
    /// Row container: fixed padding, rounded hover fill.
    func listRow(highlight: Color? = nil) -> some View {
        modifier(ListRowModifier(highlight: highlight))
    }
}

private struct ListRowModifier: ViewModifier {
    let highlight: Color?

    func body(content: Content) -> some View {
        HoverReader { hovering in
            content
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs + 1)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(highlight ?? (hovering ? DS.Palette.hover : .clear))
                )
                .animation(DS.Motion.quick, value: hovering)
        }
    }
}

/// "Meetings ······· accessory" — the one section-header treatment.
struct SectionHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(title)
                .font(DS.Typo.section)
                .foregroundStyle(DS.Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.s)
            accessory()
        }
        .padding(.horizontal, DS.Space.s)
    }
}

/// One-pixel separator in the ramp's hairline colour.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(DS.Palette.hairline)
            .frame(height: 1)
    }
}

/// A keyboard shortcut rendered as a keycap.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.Typo.mono)
            .foregroundStyle(DS.Palette.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DS.Palette.hover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(DS.Palette.hairline, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// A small status dot: amber for attention, red for live, muted at rest.
struct StatusDot: View {
    let color: Color?
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color ?? DS.Palette.textMuted.opacity(0.5))
            .frame(width: size, height: size)
    }
}
