import SwiftUI

struct MapSearchBar: View {
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    let onQueryChange: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.tr("Search places"), text: $searchText)
                .textInputAutocapitalization(.words)
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
                    onQueryChange("")
                    searchFocused.wrappedValue = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
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
            }
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
