import Foundation

/// Runs expensive preparation off the caller's actor. Replaced or cancelled
/// operations can finish internally but cannot publish their stale result.
@MainActor
final class LatestOperation<Value: Sendable> {
    private var currentID: UUID?
    private var worker: Task<Value, Error>?

    func cancel() {
        currentID = nil
        worker?.cancel()
        worker = nil
    }

    func perform(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        cancel()
        let id = UUID()
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        currentID = id
        worker = task
        defer {
            if currentID == id { currentID = nil; worker = nil }
        }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            guard currentID == id else { throw CancellationError() }
            return result
        } onCancel: { task.cancel() }
    }
}
