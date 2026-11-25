/// Waits, up to a second, for what a task started by the model has to do. A test that asserts at once, or sleeps a guessed
/// number of milliseconds and then asserts, is a test of the scheduler: it passes on a fast machine and fails on a loaded one.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
