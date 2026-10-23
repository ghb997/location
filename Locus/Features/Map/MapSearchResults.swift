import SwiftUI
import MapKit

struct MapSearchResults: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let items: [MKLocalSearchCompletion]
    let onSelect: (MKLocalSearchCompletion) -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            // Keep a short list at its natural height, including fully wrapped
            // accessible text. Longer lists yield space to the search controls.
            results.fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                results
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxHeight: maximumHeight)
        .layoutPriority(-1)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var maximumHeight: CGFloat {
        if verticalSizeClass == .compact { return 160 }
        return dynamicTypeSize.isAccessibilitySize ? 220 : 360
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items.prefix(5), id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.body.weight(.medium))
                            .foregroundStyle(LocusTheme.accent)
                            .frame(width: 36, height: 36)
                            .background(LocusTheme.accent.opacity(0.09), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LocusTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if item != items.prefix(5).last { Divider().padding(.leading, 64).opacity(0.5) }
            }
        }
    }
}
