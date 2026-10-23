import SwiftUI

struct SetupBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            LocusTheme.canvas.ignoresSafeArea()

            if !reduceTransparency {
                // A light, quiet canvas lets the glass edges pick up color.
                RadialGradient(
                    colors: [
                        Color(red: 0.67, green: 0.91, blue: 0.85).opacity(0.65),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 420
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Color(red: 0.73, green: 0.86, blue: 0.98).opacity(0.65),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 380
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [Color(red: 1, green: 0.96, blue: 0.88).opacity(0.8), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 340
                )
                .ignoresSafeArea()

                // Subtle grid suggestion of a map without competing with copy.
                GeometryReader { geo in
                    Path { path in
                        let spacing: CGFloat = 44
                        for x in stride(from: 0, through: geo.size.width, by: spacing) {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        for y in stride(from: 0, through: geo.size.height, by: spacing) {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                    }
                    .stroke(LocusTheme.accent.opacity(0.055), lineWidth: 1)
                }
                .ignoresSafeArea()
            }
        }
        .accessibilityHidden(true)
    }
}
