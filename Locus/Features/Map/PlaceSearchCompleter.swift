import Foundation
import MapKit
import Combine

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private var completer: MKLocalSearchCompleter?

    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            completer?.delegate = nil
            completer?.cancel()
            completer = nil
            results = []
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            // Each query owns its provider so a queued callback from an earlier
            // query cannot replace the current suggestions, including A → B → A.
            let request = MKLocalSearchCompleter()
            request.delegate = self
            request.resultTypes = [.address, .pointOfInterest]
            completer = request
            request.queryFragment = query
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in
            guard self.completer === completer else { return }
            self.results = items
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.completer === completer else { return }
            self.results = []
        }
    }
}
