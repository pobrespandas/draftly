import AppKit
import DraftlyCore

enum NativeSharingItem: Equatable {
    case text(String)
    case url(URL)
    case file(URL)
}

enum NativeSharingEvent {
    case selected
    case cancelled
    case completed
    case failed(Error)
}

@MainActor
protocol NativeSharingDriving: AnyObject {
    var onEvent: ((NativeSharingEvent) -> Void)? { get set }
    func canShare(_ item: NativeSharingItem) -> Bool
    func show(_ item: NativeSharingItem) throws
    func dismissPicker()
    func detach()
}

@MainActor
enum NativeSharingRequest {
    static func run(_ operation: String, _ values: [String: Any],
                    driver: (any NativeSharingDriving)? = nil, timeout: TimeInterval = 120,
                    temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                    now: @escaping @MainActor () -> Date = Date.init,
                    reportCleanupError: @escaping @MainActor (String) -> Void = { _ in }) async throws -> Bool {
        guard timeout.isFinite, timeout > 0 else { throw DraftlyError.message("The sharing timeout must be positive and finite.") }
        try Task.checkCancellation()
        let deadline = now().addingTimeInterval(timeout)
        let prepared = try SharingPreparation.make(operation, values, temporaryDirectory: temporaryDirectory)
        let request = SharingSession(prepared: prepared, driver: driver ?? SystemSharingDriver(),
                                     deadline: deadline, now: now, reportCleanupError: reportCleanupError)
        let result = try await request.run()
        try Task.checkCancellation()
        return result
    }
}

private struct SharingPreparation {
    let item: NativeSharingItem
    let folder: URL?

    static func make(_ operation: String, _ values: [String: Any], temporaryDirectory: URL) throws -> Self {
        switch operation {
        case "share": return Self(item: .text(values["text"] as? String ?? ""), folder: nil)
        case "shareURL":
            guard let raw = values["url"] as? String, let url = URL(string: raw), url.scheme != nil else {
                throw DraftlyError.message("The sharing URL is invalid.")
            }
            return Self(item: .url(url), folder: nil)
        case "shareFile":
            let name = (values["name"] as? String ?? "Draft.txt").replacingOccurrences(of: "/", with: "-")
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !name.contains("\0") else {
                throw DraftlyError.message("The shared file name is invalid.")
            }
            let folder = temporaryDirectory.appendingPathComponent("Draftly-Share-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                let file = folder.appendingPathComponent(name)
                try (values["text"] as? String ?? "").write(to: file, atomically: true, encoding: .utf8)
                return Self(item: .file(file), folder: folder)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
        default: throw DraftlyError.message("The sharing operation is unavailable.")
        }
    }
}

@MainActor
private final class SharingSession {
    // A handed-off service owns its work. Keep its file until its callback arrives.
    private static var handedOff: [UUID: SharingSession] = [:]
    private let id = UUID()
    private let prepared: SharingPreparation
    private let driver: any NativeSharingDriving
    private let now: @MainActor () -> Date
    private let reportCleanupError: @MainActor (String) -> Void
    private var continuation: CheckedContinuation<Bool, Error>?
    private var timer: Task<Void, Never>?
    private let deadline: Date
    private var serviceStarted = false
    private var disposed = false

    init(prepared: SharingPreparation, driver: any NativeSharingDriving,
         deadline: Date, now: @escaping @MainActor () -> Date, reportCleanupError: @escaping @MainActor (String) -> Void) {
        self.prepared = prepared; self.driver = driver; self.deadline = deadline
        self.now = now; self.reportCleanupError = reportCleanupError
    }

    func run() async throws -> Bool {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError())); return }
                guard now() < deadline else { finish(.failure(ActionExecutionInterruption.timeout)); return }
                let available = driver.canShare(prepared.item)
                guard !Task.isCancelled else { finish(.failure(CancellationError())); return }
                guard now() < deadline else { finish(.failure(ActionExecutionInterruption.timeout)); return }
                guard available else {
                    finish(.failure(DraftlyError.message("No sharing service is available for these items.")))
                    return
                }
                driver.onEvent = { [weak self] event in self?.received(event) }
                timer = Task { @MainActor [self] in
                    do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSince(now())))) } catch { return }
                    finish(.failure(ActionExecutionInterruption.timeout))
                }
                do { try driver.show(prepared.item) }
                catch { finish(.failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [self] in finish(.failure(CancellationError())) }
        }
    }

    private func received(_ event: NativeSharingEvent) {
        guard !disposed else { return }
        switch event {
        case .selected:
            guard !serviceStarted else { return }
            serviceStarted = true
            Self.handedOff[id] = self
            if continuation != nil, now() >= deadline { finish(.failure(ActionExecutionInterruption.timeout)) }
        case .cancelled:
            guard !serviceStarted else { return }
            finish(now() >= deadline ? .failure(ActionExecutionInterruption.timeout) : .success(false))
        case .completed:
            serviceStarted = false
            if continuation != nil {
                finish(now() >= deadline ? .failure(ActionExecutionInterruption.timeout) : .success(true))
            } else { dispose() }
        case .failed(let error):
            serviceStarted = false
            if continuation != nil {
                let cocoa = error as NSError
                let result: Result<Bool, Error> = cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSUserCancelledError ? .success(false) : .failure(error)
                finish(now() >= deadline ? .failure(ActionExecutionInterruption.timeout) : result)
            } else { dispose() }
        }
    }

    private func finish(_ result: Result<Bool, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel(); timer = nil
        driver.dismissPicker()
        if !serviceStarted { dispose() }
        continuation.resume(with: result)
    }

    private func dispose() {
        guard !disposed else { return }
        disposed = true
        driver.onEvent = nil
        driver.detach()
        Self.handedOff.removeValue(forKey: id)
        if let folder = prepared.folder {
            do { try FileManager.default.removeItem(at: folder) }
            catch { reportCleanupError("The sharing temporary file could not be removed: " + error.localizedDescription) }
        }
    }
}

@MainActor
private final class SystemSharingDriver: NSObject, NativeSharingDriving, @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    var onEvent: ((NativeSharingEvent) -> Void)?
    private var picker: NSSharingServicePicker?
    private var service: NSSharingService?
    private var items: [Any] = []

    private func nativeItem(_ item: NativeSharingItem) -> Any {
        switch item {
        case .text(let text): return text
        case .url(let url), .file(let url): return url
        }
    }
    func canShare(_ item: NativeSharingItem) -> Bool {
        let items = [nativeItem(item)]
        return NSSharingService.sharingServices(forItems: items).contains { $0.canPerform(withItems: items) }
    }
    func show(_ item: NativeSharingItem) throws {
        guard let view = NSApp.keyWindow?.contentView else {
            throw DraftlyError.message("Open a Draftly window before sharing.")
        }
        items = [nativeItem(item)]
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self; self.picker = picker
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 20, width: 1, height: 1), of: view, preferredEdge: .minY)
    }
    func dismissPicker() {
        picker?.delegate = nil; picker?.close(); picker = nil
    }
    func detach() {
        dismissPicker()
        service?.delegate = nil; service = nil
        items = []; onEvent = nil
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices: [NSSharingService]) -> [NSSharingService] {
        proposedSharingServices.filter { $0.canPerform(withItems: items) }
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        sharingService.delegate = self
        service = sharingService
        return self
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard let service else { onEvent?(.cancelled); return }
        self.service = service; service.delegate = self
        onEvent?(.selected)
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { onEvent?(.completed) }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { onEvent?(.failed(error)) }
}
