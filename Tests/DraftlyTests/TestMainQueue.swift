import Foundation

@MainActor
enum TestMainQueue {
    static func drain(turns: Int = 3) async {
        for _ in 0..<turns {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}
