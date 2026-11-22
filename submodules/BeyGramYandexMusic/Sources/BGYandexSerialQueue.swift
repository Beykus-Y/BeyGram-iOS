import Foundation

/// Runs asynchronous operations one at a time, in the order they were queued. Each operation calls its `done` exactly once,
/// when it has finished, so the next one can start.
final class BGYandexSerialQueue {
    private let lock = NSLock()
    private var pending: [(@escaping () -> Void) -> Void] = []
    private var busy = false

    func run(_ operation: @escaping (@escaping () -> Void) -> Void) {
        lock.lock()
        pending.append(operation)
        let start = !busy
        busy = true
        lock.unlock()
        if start {
            next()
        }
    }

    private func next() {
        lock.lock()
        if pending.isEmpty {
            busy = false
            lock.unlock()
            return
        }
        let operation = pending.removeFirst()
        lock.unlock()
        operation {
            self.next()
        }
    }
}

/// Delivers a completion on the main queue, so screens can use a result directly.
func bgYandexMain<T>(_ completion: @escaping (Result<T, BGYandexError>) -> Void) -> (Result<T, BGYandexError>) -> Void {
    return { result in
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
