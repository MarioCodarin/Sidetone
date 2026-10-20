import SwiftUI

/// The design system: every spacing, type, radius, colour and motion value the UI uses lives
/// here, so the look can be changed in one place.
///
/// Spacing follows a 4 pt grid. Colours are semantic (`.primary`, `.secondary`, the user's
/// accent) apart from the two roles with a fixed meaning: red = recording, orange = needs attention.
enum DS {

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 10
    }

    /// System type (SF Pro). Nothing smaller than 11 pt.
    enum Typo {
        static let title = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let secondary = Font.system(size: 11)
        static let section = Font.system(size: 11, weight: .semibold)
        static let timer = Font.system(size: 22, weight: .regular).monospacedDigit()
    }

    enum Palette {
        /// Recording, and anything that starts one.
        static let record = Color.red
        /// Paused, "not mixed yet", missing permission.
        static let attention = Color.orange
        /// Resting fill of controls and bars.
        static let track = Color.primary.opacity(0.10)
        static let hover = Color.primary.opacity(0.07)
        static let pressed = Color.primary.opacity(0.14)
    }

    enum Motion {
        /// Hover, press and focus feedback.
        static let quick = Animation.easeOut(duration: 0.15)
        /// Content appearing or disappearing.
        static let standard = Animation.easeInOut(duration: 0.2)
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

// MARK: - Button styles

/// Full-width action button. `prominent` fills with `tint`; otherwise a quiet neutral fill.
struct ActionButtonStyle: ButtonStyle {
    var tint: Color = DS.Palette.record
    var prominent = true
    var height: CGFloat = 32

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Content(configuration: configuration, tint: tint, prominent: prominent, height: height)
    }

    private struct Content: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let prominent: Bool
        let height: CGFloat

        var body: some View {
            HoverReader { hovering in
                configuration.label
                    .font(DS.Typo.title)
                    .foregroundStyle(prominent ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(neutral(hovering)))
                    )
                    .brightness(prominent ? (configuration.isPressed ? -0.1 : hovering ? 0.06 : 0) : 0)
                    .scaleEffect(configuration.isPressed ? 0.985 : 1)
                    .opacity(isEnabled ? 1 : 0.4)
                    .animation(DS.Motion.quick, value: configuration.isPressed)
                    .animation(DS.Motion.quick, value: hovering)
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            }
        }

        private func neutral(_ hovering: Bool) -> Color {
            Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.12 : 0.08)
        }
    }
}

/// A square icon-only button that shows its hit area on hover.
struct IconButtonStyle: ButtonStyle {
    /// Foreground while hovered or pressed; at rest the icon is `.secondary`.
    var hoverTint: Color = .primary
    /// Foreground at rest; nil means `.secondary`.
    var restTint: Color?
    var size: CGFloat = 24

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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hovering || configuration.isPressed ? AnyShapeStyle(hoverTint) : restTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
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

/// A text-and-icon button for quiet, low-priority actions (footer, "Show all").
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HoverReader { hovering in
            configuration.label
                .font(DS.Typo.secondary)
                .foregroundStyle(hovering || configuration.isPressed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
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

/// Makes a whole list row a button: hover and press fill, no chrome at rest.
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

// MARK: - Rows and sections

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

/// "MEETINGS ····· accessory" — the one section-header treatment.
struct SectionHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack {
            Text(title)
                .font(DS.Typo.section)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.s)
            accessory()
        }
        .padding(.horizontal, DS.Space.s)
    }
}
