import Foundation

@MainActor extension ActionRunner {
    func executeAsync(_ action: DraftAction, note: Note, session: ActionExecutionSession) async throws {
        guard hostOperationTimeout.isFinite, hostOperationTimeout > 0 else {
            throw DraftlyError.message("The host operation timeout must be positive and finite.")
        }
        let steps = try ActionStepExpansion.expand(action, actions: library.actions)
        let initialStepID = UUID()
        bridgeStepID = initialStepID
        let worker = ActionScriptWorker(executionID: session.id, stepID: initialStepID,
            hostTimeout: hostOperationTimeout) { [weak self] request in
                await self?.receive(request) ?? "{\"error\":\"The action was closed.\"}"
            }
        cancelWorker = { worker.cancel() }
        do {
            try await worker.start(bootstrapSource(action, note: note, steps: steps))
            func performSteps(_ items: [ActionStep], owner: UUID, path: Set<UUID>) async throws {
                for step in items where step.isEnabled != false {
                    try checkCancellation()
                    try Task.checkCancellation()
                    session.enter(actionID: owner, step: step)
                    bridgeStepID = step.id
                    if step.type == "includeAction" {
                        let current = library.notes.first(where: { $0.id == note.id }) ?? note
                        let included = try ActionStepExpansion.resolve(step, actions: library.actions) { try renderTemplate($0, note: current) }
                        let includedSteps = try ActionStepExpansion.expand(included, actions: library.actions, path: path)
                        try await worker.evaluateSource(additionalConfigurationSource(action, steps: includedSteps))
                        try await performSteps(included.steps, owner: included.id, path: path.union([included.id]))
                        continue
                    }
                    if step.type == "script" {
                        _ = try await worker.run(source: step.values["script"] ?? step.values["source"] ?? "", stepID: step.id,
                            asynchronous: ["true", "1"].contains(step.values["allowAsync"] ?? step.values["allowAsynchronous"] ?? "false"),
                            timeout: scriptTimeout, synchronousTimeout: synchronousScriptTimeout)
                    } else {
                        let text = step.values["template"] ?? step.values["text"] ?? "[[draft]]"
                        let current = library.notes.first(where: { $0.id == note.id }) ?? note
                        let rendered = try renderTemplate(text, note: current)
                        var updates: [String] = []
                        let suspended = try await performSuspendingStep(step, text: text, rendered: rendered, current: current, evaluate: { updates.append($0) })
                        if let suspended {
                            guard suspended else { throw ActionExecutionInterruption.cancelled }
                        } else {
                            let perform = {
                                try ActionStepExecutor(runner: self).performNative(step, text: text, rendered: rendered, current: current,
                                    evaluate: { updates.append($0) }, executeIncluded: { _, _ in
                                        throw DraftlyError.message("The included action was not expanded.")
                                    })
                            }
                            let completed = try ["insertText", "createDraft"].contains(step.type) ? withScriptMutation(perform) : perform()
                            guard completed else { throw ActionExecutionInterruption.cancelled }
                        }
                        if !updates.isEmpty { try await worker.evaluateSource(updates.joined(separator: "\n")) }
                    }
                    try await worker.evaluateSource("__tags=\(try json(customTags));")
                }
            }
            try await performSteps(action.steps, owner: action.id, path: [action.id])
            try checkCancellation()
            try Task.checkCancellation()
            try flushEditor()
            try applySuccessEffects(action, noteID: note.id)
            bridgeStepID = nil
            await worker.close()
            cancelWorker = nil
        } catch {
            bridgeStepID = nil
            await worker.close()
            cancelWorker = nil
            throw error
        }
    }

    func recordScriptSave(_ note: Note) {
        if asyncExecutionID != nil { scriptNoteContents[note.id] = note.content }
    }

    func validateScriptNote(_ id: UUID) throws {
        guard asyncExecutionID != nil, let previous = scriptNoteContents[id] else { return }
        guard let stored = library.notes.first(where: { $0.id == id }) else {
            cancel()
            throw DraftlyError.message("The draft is no longer available. The pending action was cancelled.")
        }
        guard stored.content != previous else { return }
        cancel()
        if editor.noteID == id, editor.content == previous || isApplyingScriptCommand {
            editor.content = stored.content
            editor.acknowledgeSaved(stored)
            editor.selection = editor.safeSelection
            editor.synchronizeScriptEdit?()
        }
        throw DraftlyError.message("The draft changed outside this action. The pending action was cancelled.")
    }

    private func receive(_ request: ActionBridgeRequest) async -> String {
        do {
            guard activeSession?.id == request.executionID, bridgeStepID == request.stepID,
                  activeSession?.report == nil else { throw DraftlyError.message("The action was closed.") }
            guard Date() < request.deadline else { throw ActionExecutionInterruption.timeout }
            try checkCancellation()
            if request.operation == "ui", host?.supportsAsync("transcribe") == true,
               let values = try JSONSerialization.jsonObject(with: Data(request.payload.utf8)) as? [String: Any],
               values["operation"] as? String == "transcribe" {
                guard uiOperation != nil else { throw DraftlyError.message("This action needs an active Draftly editor window.") }
                let response = try await platformAsync("transcribe", payload: "{}")
                try checkCancellation()
                guard activeSession?.id == request.executionID, bridgeStepID == request.stepID else {
                    throw DraftlyError.message("The action was closed.")
                }
                return response
            }
            if request.operation == "http" {
                let response = await ScriptHTTP.requestSerialized(request.payload)
                try Task.checkCancellation()
                try checkCancellation()
                guard activeSession?.id == request.executionID, bridgeStepID == request.stepID else {
                    throw DraftlyError.message("The action was closed.")
                }
                return response
            }
            if host?.supportsAsync(request.operation) == true {
                let response = try await platformAsync(request.operation, payload: request.payload)
                guard activeSession?.id == request.executionID, bridgeStepID == request.stepID else {
                    throw DraftlyError.message("The action was closed.")
                }
                return response
            }
            let values = (try? JSONSerialization.jsonObject(with: Data(request.payload.utf8))) as? [String: Any] ?? [:]
            let result: Any?
            if request.operation == "requireScript" { result = try platform("requireScript", values) }
            else { result = try dispatch(request.operation, values: values) }
            try checkCancellation()
            return try json(["value": result ?? NSNull()])
        } catch {
            if (error as? ActionExecutionInterruption) == .timeout { return (try? json(["error": error.localizedDescription, "termination": "timeout"])) ?? "{}" }
            return (try? json(["error": error.localizedDescription])) ?? "{\"error\":\"The action failed.\"}"
        }
    }
}
