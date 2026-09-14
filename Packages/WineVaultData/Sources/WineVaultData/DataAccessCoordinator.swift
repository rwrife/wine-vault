actor DataAccessCoordinator {
    // One process-wide queue also covers separate stacks opening the same vault.
    // Serializing independent vault roots is an intentional, small MVP tradeoff.
    static let sharedStorage = DataAccessCoordinator()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withExclusiveAccess<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async rethrows -> Value {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }
}
