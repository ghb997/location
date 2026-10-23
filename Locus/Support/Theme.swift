import SwiftUI

enum LocusTheme {
    static let canvas = Color(red: 0.953, green: 0.969, blue: 0.980)
    static let ink = Color(red: 0.082, green: 0.176, blue: 0.231)
    static let accent = Color(red: 0.031, green: 0.498, blue: 0.522)
    static let accentSecondary = Color(red: 0.639, green: 0.357, blue: 0.106)
    static let danger = Color(red: 0.769, green: 0.243, blue: 0.318)
    static let panelStroke = Color.white.opacity(0.85)
    static let statusGood = Color(red: 0.087, green: 0.427, blue: 0.310)
    static let statusWarn = Color(red: 0.588, green: 0.337, blue: 0.059)
    static let statusBad = danger

    /// A fine highlight/shade edge for the material fallback. iOS 26 draws its
    /// own optical boundary, so it does not receive this decorative overlay.
    static let glassEdge = LinearGradient(
        colors: [.white.opacity(0.96), .white.opacity(0.35), ink.opacity(0.13), .white.opacity(0.72)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum LocusGlassStyle {
    case regular
    case clear
    case interactive
}

/// One shared surface policy keeps floating chrome readable on a busy map.
/// Reduced transparency uses a solid surface on every supported OS.
struct LocusGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var style: LocusGlassStyle
    var shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    shape.fill(Color.white)
                    if let tint { shape.fill(tint.opacity(0.18)) }
                }
                .overlay(shape.stroke(border, lineWidth: 1))
                .contentShape(shape)
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(glass, in: shape)
                .overlay {
                    if contrast == .increased { shape.stroke(border, lineWidth: 1) }
                }
                .contentShape(shape)
        } else {
            content
                .background {
                    if contrast == .increased {
                        shape.fill(.regularMaterial)
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }
                    shape.fill(Color.white.opacity(style == .clear ? 0.04 : 0.12))
                    if let tint { shape.fill(tint.opacity(0.14)) }
                }
                .overlay {
                    if contrast == .increased { shape.stroke(border, lineWidth: 1) }
                    else { shape.stroke(LocusTheme.glassEdge, lineWidth: 0.8) }
                }
                .shadow(color: LocusTheme.ink.opacity(0.08), radius: 14, y: 6)
                .shadow(color: LocusTheme.ink.opacity(0.035), radius: 2, y: 1)
                .contentShape(shape)
        }
    }

    private var border: Color {
        contrast == .increased ? Color.primary.opacity(0.45) : LocusTheme.panelStroke
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g: Glass = style == .clear && contrast != .increased ? .clear : .regular
        if style == .interactive && !reduceMotion { g = g.interactive() }
        if let tint { g = g.tint(tint) }
        return g
    }
}

/// Group neighboring floating controls, while retaining their separate hit areas.
struct LocusGlassContainer<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

/// Subtle color beneath sheet content; controls keep their own system materials.
struct LocusSheetBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            LocusTheme.canvas
            if !reduceTransparency {
                RadialGradient(colors: [LocusTheme.accent.opacity(0.09), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 460)
                RadialGradient(colors: [Color.cyan.opacity(0.08), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 420)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct LocusActionModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let prominent: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            if prominent {
                content.buttonStyle(.borderedProminent).tint(tint ?? LocusTheme.accent).foregroundStyle(.white)
            } else {
                content.buttonStyle(.bordered).tint(tint ?? LocusTheme.ink).foregroundStyle(tint ?? LocusTheme.ink)
            }
        } else if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(tint ?? LocusTheme.accent).foregroundStyle(.white)
            } else {
                content.buttonStyle(.glass).tint(tint ?? LocusTheme.accent).foregroundStyle(tint ?? LocusTheme.ink)
            }
        } else {
            content.buttonStyle(LocusMaterialButtonStyle(prominent: prominent, tint: tint ?? LocusTheme.accent))
        }
    }
}

private struct LocusMaterialButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    let prominent: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(prominent ? .white : LocusTheme.ink)
            .background {
                Capsule().fill(.ultraThinMaterial)
                if prominent { Capsule().fill(tint) }
            }
            .overlay(Capsule().stroke(LocusTheme.glassEdge, lineWidth: 0.8))
            .shadow(color: LocusTheme.ink.opacity(0.08), radius: 10, y: 4)
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension View {
    func locusActionStyle(prominent: Bool = false, tint: Color? = nil) -> some View {
        modifier(LocusActionModifier(prominent: prominent, tint: tint))
    }

    func locusSheetBackdrop() -> some View {
        background { LocusSheetBackground() }
            .presentationBackground(.regularMaterial)
            .preferredColorScheme(.light)
            .tint(LocusTheme.accent)
            .presentationCornerRadius(32)
            .presentationDragIndicator(.visible)
    }

    func locusGlass<S: Shape>(
        _ style: LocusGlassStyle = .regular,
        tint: Color? = nil,
        in shape: S
    ) -> some View {
        modifier(LocusGlassModifier(style: style, shape: shape, tint: tint))
    }

    func locusGlass(_ style: LocusGlassStyle = .regular, tint: Color? = nil) -> some View {
        locusGlass(style, tint: tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
