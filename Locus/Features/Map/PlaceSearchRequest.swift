import MapKit

/// MapKit search cancellation is delivered on the same actor as its owner.
@MainActor
final class PlaceSearchRequest {
    private let operation: MKLocalSearch

    init(completion: MKLocalSearchCompletion) {
        operation = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
    }

    func response() async throws -> MKLocalSearch.Response {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await operation.start()
        } onCancel: {
            Task { @MainActor [weak self] in self?.operation.cancel() }
        }
    }
}
