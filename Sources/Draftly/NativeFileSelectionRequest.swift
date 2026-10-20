import AppKit
import DraftlyCore

enum NativeFileSelection: Equatable {
    case save(name: String)
    case folder(name: String)
}

typealias NativeFileSelector = @MainActor (NativeFileSelection) async throws -> URL?

@MainActor
enum NativeFileSelectionRequest {
    typealias Begin = @MainActor (NativeFileSelection, @escaping @MainActor @Sendable (URL?) -> Void) -> (() -> Void)

    static func select(_ selection: NativeFileSelection, timeout: TimeInterval = 120,
                       now: @escaping @MainActor () -> Date = Date.init,
                       begin: Begin = beginSystemPanel) async throws -> URL? {
        guard timeout.isFinite, timeout > 0 else {
            throw DraftlyError.message("The file selection timeout must be positive and finite.")
        }
        try Task.checkCancellation()
        return try await FileSelectionWait().run(selection, timeout: timeout, deadline: now().addingTimeInterval(timeout), now: now, begin: begin)
    }

    private static func beginSystemPanel(_ selection: NativeFileSelection,
                                         completion: @escaping @MainActor @Sendable (URL?) -> Void) -> (() -> Void) {
        let panel: NSSavePanel
        switch selection {
        case .save(let name):
            panel = NSSavePanel(); panel.nameFieldStringValue = name
        case .folder(let name):
            let folder = NSOpenPanel()
            folder.canChooseFiles = false; folder.canChooseDirectories = true
            folder.message = "Choose the folder for \(name)."
            panel = folder
        }
        panel.isReleasedWhenClosed = false
        panel.begin { [weak panel] response in
            Task { @MainActor in completion(response == .OK ? panel?.url : nil) }
        }
        return { panel.cancel(nil) }
    }
}

@MainActor
private final class FileSelectionWait {
    private var continuation: CheckedContinuation<URL?, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var closePanel: (() -> Void)?

    func run(_ selection: NativeFileSelection, timeout: TimeInterval, deadline: Date,
             now: @escaping @MainActor () -> Date, begin: NativeFileSelectionRequest.Begin) async throws -> URL? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError())); return }
                timeoutTask = Task { @MainActor [self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    finish(.failure(ActionExecutionInterruption.timeout))
                }
                let close = begin(selection) { [weak self] url in
                    guard let self else { return }
                    if now() >= deadline { self.finish(.failure(ActionExecutionInterruption.timeout)) }
                    else { self.finish(.success(url)) }
                }
                if self.continuation != nil { closePanel = close }
                else { close() }
            }
        } onCancel: {
            Task { @MainActor [self] in finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<URL?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        let close = closePanel
        closePanel = nil
        close?()
        continuation.resume(with: result)
    }
}
