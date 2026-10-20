import Foundation

@MainActor extension ActionRunner {
    func executeAsync(_ initialAction: DraftAction, note: Note, session: ActionExecutionSession) async throws {
        guard hostOperationTimeout.isFinite, hostOperationTimeout > 0 else {
            throw DraftlyError.message("The host operation timeout must be positive and finite.")
        }
        let steps = try ActionStepExpansion.expand(initialAction, actions: library.actions)
        var configurationSteps = steps
        var action = try await prepareInitialConfigurationAsync(initialAction, steps: steps)
        let initialStepID = UUID()
        bridgeStepID = initialStepID
        let authority = ActionBridgeRequestAuthority()
        let worker = ActionScriptWorker(executionID: session.id, stepID: initialStepID,
            hostTimeout: hostOperationTimeout, requestAuthority: authority) { [weak self] request in
                await self?.receive(request, authority: authority) ?? "{\"error\":\"The action was closed.\"}"
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
                        let included = try await ActionTemplateBuilder.build(render: { try await self.renderTemplateAsync($0, note: current) }) { render in
                            try ActionStepExpansion.resolve(step, actions: self.library.actions, render: render)
                        }
                        let includedSteps = try ActionStepExpansion.expand(included, actions: library.actions, path: path)
                        configurationSteps += includedSteps
                        action = try await prepareInitialConfigurationAsync(action, steps: configurationSteps)
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
                        let rendered = try await renderTemplateAsync(text, note: current)
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

    func receive(_ request: ActionBridgeRequest, authority: ActionBridgeRequestAuthority) async -> String {
        do {
            guard activeSession?.id == request.executionID, bridgeStepID == request.stepID,
                  activeSession?.report == nil else { throw DraftlyError.message("The action was closed.") }
            guard Date() < request.deadline else { throw ActionExecutionInterruption.timeout }
            guard authority.consume(request) else { throw DraftlyError.message("The host request is unknown or already consumed.") }
            try checkCancellation()
            if request.operation == "ui",
               let values = try JSONSerialization.jsonObject(with: Data(request.payload.utf8)) as? [String: Any],
               let operation = values["operation"] as? String,
               ["transcribe", "dictate", "arrange"].contains(operation), host?.supportsAsync(operation == "arrange" ? "arrangeText" : operation) == true {
                guard operation == "arrange" || uiOperation != nil else { throw DraftlyError.message("This action needs an active Draftly editor window.") }
                let args = values["args"] as? [Any] ?? []
                let payload: String
                switch operation {
                case "dictate": payload = try json(["locale": args.first as? String ?? ""])
                case "arrange": payload = try json(["text": args.first as? String ?? ""])
                default: payload = "{}"
                }
                let response = try await platformAsync(operation == "arrange" ? "arrangeText" : operation, payload: payload)
                try checkCancellation()
                guard activeSession?.id == request.executionID, bridgeStepID == request.stepID else {
                    throw DraftlyError.message("The action was closed.")
                }
                return response
            }
            if request.operation == "template",
               let values = try JSONSerialization.jsonObject(with: Data(request.payload.utf8)) as? [String: Any],
               case .template(let text, let input, let tags) = try ScriptCommand(operation: "template", values: values) {
                let result = try await renderTemplateAsync(text, note: input.resolve(in: library), tags: tags)
                try checkCancellation()
                guard activeSession?.id == request.executionID, bridgeStepID == request.stepID else { throw DraftlyError.message("The action was closed.") }
                return try json(["value": result])
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
            if let interruption = error as? ActionExecutionInterruption {
                return (try? json(["error": error.localizedDescription, "termination": interruption == .timeout ? "timeout" : "cancelled"])) ?? "{}"
            }
            return (try? json(["error": error.localizedDescription])) ?? "{\"error\":\"The action failed.\"}"
        }
    }
}
