import SwiftUI

struct JoystickPad: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onChange: (CGVector) -> Void

    @State private var dragOffset: CGSize = .zero
    private let radius: CGFloat = 52

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: radius * 2 + 28, height: radius * 2 + 28)
                .locusGlass(.regular, in: Circle())

            Circle()
                .stroke(LocusTheme.accent.opacity(0.2), lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
                .accessibilityHidden(true)

            Image(systemName: "plus")
                .font(.system(size: 46, weight: .ultraLight))
                .foregroundStyle(LocusTheme.accent.opacity(0.28))
                .accessibilityHidden(true)

            Circle()
                .fill(LinearGradient(colors: [.white, LocusTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(LocusTheme.accent.opacity(0.3), lineWidth: 1))
                .overlay {
                    Circle().fill(LocusTheme.accent).frame(width: 10, height: 10)
                }
                .shadow(color: LocusTheme.accent.opacity(0.16), radius: 8, y: 3)
                .offset(dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let limited = clamp(value.translation, radius: radius)
                            dragOffset = limited
                            onChange(CGVector(dx: limited.width / radius, dy: limited.height / radius))
                        }
                        .onEnded { _ in
                            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7)) {
                                dragOffset = .zero
                            }
                            onChange(.zero)
                        }
                )
        }
        .accessibilityLabel(L10n.tr("Movement joystick"))
        .accessibilityHint(L10n.tr("Drag to move. Release to hold position."))
        .onDisappear { onChange(.zero) }
    }

    private func clamp(_ translation: CGSize, radius: CGFloat) -> CGSize {
        let length = sqrt(translation.width * translation.width + translation.height * translation.height)
        guard length > radius else { return translation }
        let scale = radius / length
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }
}
