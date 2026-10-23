import SwiftUI

enum LocusTheme {
    static let accent = Color(red: 0.35, green: 0.78, blue: 0.72)
    static let accentSecondary = Color(red: 0.95, green: 0.55, blue: 0.28)
    static let danger = Color(red: 0.92, green: 0.32, blue: 0.36)
    static let panelStroke = Color.white.opacity(0.18)
    static let statusGood = Color(red: 0.30, green: 0.86, blue: 0.55)
    static let statusWarn = Color(red: 0.98, green: 0.78, blue: 0.28)
    static let statusBad = Color(red: 0.92, green: 0.32, blue: 0.36)
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
    @Environment(\.colorScheme) private var colorScheme

    var style: LocusGlassStyle
    var shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    shape.fill(Color(uiColor: .secondarySystemBackground))
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
                    if let tint { shape.fill(tint.opacity(0.22)) }
                }
                .overlay(shape.stroke(border, lineWidth: 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 14, y: 6)
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
            Color(uiColor: .systemGroupedBackground)
            if !reduceTransparency {
                RadialGradient(colors: [LocusTheme.accent.opacity(0.13), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 460)
                RadialGradient(colors: [Color.blue.opacity(0.08), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 420)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func locusSheetBackdrop() -> some View {
        presentationBackground { LocusSheetBackground() }
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
