import SwiftUI
import MapKit

struct MapSearchResults: View {
    let items: [MKLocalSearchCompletion]
    let onSelect: (MKLocalSearchCompletion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items.prefix(5), id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(LocusTheme.accent)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if item != items.prefix(5).last { Divider().padding(.leading, 56).opacity(0.4) }
            }
        }
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
