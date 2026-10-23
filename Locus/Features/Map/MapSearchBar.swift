import SwiftUI

struct MapSearchBar: View {
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    let onQueryChange: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(LocusTheme.accent)
                .frame(width: 32, height: 32)
                .background(LocusTheme.accent.opacity(0.09), in: Circle())
                .accessibilityHidden(true)
            TextField(L10n.tr("Search places"), text: $searchText)
                .textInputAutocapitalization(.words)
                .foregroundStyle(LocusTheme.ink)
                .tint(LocusTheme.accent)
                .focused(searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused.wrappedValue = false
                }
                .onChange(of: searchText) { _, value in
                    onQueryChange(value)
                }
            if searchFocused.wrappedValue || !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused.wrappedValue = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Clear and dismiss keyboard"))
            }
            if searchFocused.wrappedValue {
                Button(L10n.tr("Done")) {
                    searchFocused.wrappedValue = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(LocusTheme.accent)
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 56)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
