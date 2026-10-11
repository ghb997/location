import CoreLocation
import SwiftUI

struct CoordinateEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var system: CoordinateSystem = .wgs84
    @State private var error: String?
    var onSelect: (CLLocationCoordinate2D) -> Void

    private var normalized: CLLocationCoordinate2D? {
        guard let lat = Double(latitude), let lon = Double(longitude) else { return nil }
        return try? CoordinateTransform.normalize(.init(latitude: lat, longitude: lon), from: system)
    }

    private var validationMessage: String? {
        guard !latitude.isEmpty || !longitude.isEmpty else { return nil }
        guard let lat = Double(latitude), let lon = Double(longitude) else { return L10n.tr("Enter valid latitude and longitude.") }
        do { _ = try CoordinateTransform.normalize(.init(latitude: lat, longitude: lon), from: system); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.tr("Latitude"), text: $latitude).keyboardType(.numbersAndPunctuation)
                TextField(L10n.tr("Longitude"), text: $longitude).keyboardType(.numbersAndPunctuation)
                Picker(L10n.tr("Input coordinate system"), selection: $system) {
                    ForEach(CoordinateSystem.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if let point = normalized {
                    LabeledContent("WGS-84", value: String(format: "%.7f, %.7f", point.latitude, point.longitude))
                }
                if let error { Text(error).foregroundStyle(.red) }
                else if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
                Text(L10n.tr("This prepares a map pin. Apply it from the map when ready."))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(L10n.tr("Use these coordinates"), action: select).disabled(normalized == nil)
            }
            .navigationTitle(L10n.tr("Enter coordinates"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Cancel")) { dismiss() } } }
        }
    }

    private func select() {
        guard let point = normalized else {
            error = L10n.tr("Enter valid latitude and longitude.")
            return
        }
        onSelect(point)
        dismiss()
    }
}
