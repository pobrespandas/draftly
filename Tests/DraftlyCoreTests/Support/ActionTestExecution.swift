@testable import DraftlyCore

@MainActor
enum ActionTestExecution {
    static func succeeds(_ action: DraftAction, runner: ActionRunner, worker: Bool) async -> Bool {
        if worker { return await runner.runAsync(action).result.succeeded }
        return runner.run(action)
    }
}
