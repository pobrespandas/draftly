import AppKit
import DraftlyCore

struct NativePrintConfiguration: Equatable {
    enum Format: String { case text, html }
    let text: String
    let format: Format
    let topMargin: CGFloat
    let bottomMargin: CGFloat
    let leftMargin: CGFloat
    let rightMargin: CGFloat

    init(_ values: [String: Any]) throws {
        text = values["text"] as? String ?? ""
        let raw = (values["format"] as? String ?? values["printFormat"] as? String ?? "Text").lowercased()
        guard let format = Format(rawValue: raw == "plain" ? "text" : raw) else { throw DraftlyError.message("The print format is invalid.") }
        self.format = format
        func margin(_ key: String) throws -> CGFloat {
            guard let value = values[key] else { return 72 }
            let number: Double?
            if let text = value as? String { number = Double(text) }
            else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { number = value.doubleValue }
            else { number = nil }
            guard let number, number.isFinite, number >= 0 else { throw DraftlyError.message("The print margin \(key) must be a finite nonnegative number.") }
            return CGFloat(number)
        }
        topMargin = try margin("topMargin"); bottomMargin = try margin("bottomMargin")
        leftMargin = try margin("leftMargin"); rightMargin = try margin("rightMargin")
    }
}

struct NativePrintPageGeometry {
    let contentSize: NSSize
    init(paperSize: NSSize, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat, scale: CGFloat = 1) throws {
        guard paperSize.width.isFinite, paperSize.height.isFinite, paperSize.width > 0, paperSize.height > 0,
              scale.isFinite, scale > 0,
              [top, bottom, left, right].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw DraftlyError.message("The print page geometry is invalid.")
        }
        let width = paperSize.width - left - right, height = paperSize.height - top - bottom
        guard width > 0, height > 0 else { throw DraftlyError.message("The print margins leave no printable area.") }
        let scaledWidth = width / scale, scaledHeight = height / scale
        guard scaledWidth.isFinite, scaledHeight.isFinite, scaledWidth > 0, scaledHeight > 0 else {
            throw DraftlyError.message("The print page geometry is invalid.")
        }
        contentSize = NSSize(width: scaledWidth, height: scaledHeight)
    }
}

@MainActor enum NativePrintLayout {
    static func makeOperation(_ configuration: NativePrintConfiguration, printInfo: NSPrintInfo) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.topMargin = configuration.topMargin; info.bottomMargin = configuration.bottomMargin
        info.leftMargin = configuration.leftMargin; info.rightMargin = configuration.rightMargin
        info.horizontalPagination = .clip; info.verticalPagination = .automatic
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        let view = try makeView(configuration, paperSize: info.paperSize, scalingFactor: info.scalingFactor)
        let operation = NSPrintOperation(view: view, printInfo: info)
        // AppKit calls pagination and the delegate on the printing thread.
        // The text view and delegate require MainActor.
        operation.canSpawnSeparateThread = false
        return operation
    }

    static func makeView(_ configuration: NativePrintConfiguration, paperSize: NSSize, scalingFactor: CGFloat = 1) throws -> NativePrintTextView {
        let geometry = try NativePrintPageGeometry(paperSize: paperSize, top: configuration.topMargin, bottom: configuration.bottomMargin,
            left: configuration.leftMargin, right: configuration.rightMargin, scale: scalingFactor)
        let view = NativePrintTextView(frame: .zero)
        if configuration.format == .html {
            view.textStorage?.setAttributedString(try NSAttributedString(data: Data(configuration.text.utf8), options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil))
        } else { view.string = configuration.text }
        view.apply(geometry)
        return view
    }
}

@MainActor final class NativePrintTextView: NSTextView {
    private(set) var layoutError: Error?
    func apply(_ geometry: NativePrintPageGeometry) {
        isHorizontallyResizable = false; isVerticallyResizable = false
        textContainerInset = .zero
        guard let container = textContainer, let manager = layoutManager else { return }
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false; container.heightTracksTextView = false
        container.containerSize = NSSize(width: geometry.contentSize.width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let extra = manager.extraLineFragmentTextContainer === container ? manager.extraLineFragmentRect.maxY : 0
        frame = NSRect(x: 0, y: 0, width: geometry.contentSize.width, height: max(1, ceil(max(used.maxY, extra))))
        layoutError = nil
    }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        if let info = NSPrintOperation.current?.printInfo {
            do {
                apply(try NativePrintPageGeometry(paperSize: info.paperSize, top: info.topMargin, bottom: info.bottomMargin,
                    left: info.leftMargin, right: info.rightMargin, scale: info.scalingFactor))
            } catch {
                layoutError = error; range.pointee = NSRange(location: 1, length: 0); return true
            }
        }
        return super.knowsPageRange(range)
    }
}

@MainActor protocol NativePrintDriver: AnyObject {
    var onFinish: ((Result<Bool, Error>) -> Void)? { get set }
    func start()
    func cancelOwnedPresentation()
    func detach()
}

@MainActor enum NativePrintRequest {
    static func run(_ values: [String: Any], timeout: TimeInterval = 120,
                    now: @escaping @MainActor () -> Date = { Date() },
                    makeDriver: @MainActor (NativePrintConfiguration) throws -> any NativePrintDriver = { try SheetPrintDriver($0) }) async throws -> Bool {
        try Task.checkCancellation()
        guard timeout.isFinite, timeout > 0 else { throw DraftlyError.message("The print timeout must be positive and finite.") }
        let deadline = now().addingTimeInterval(timeout)
        let configuration = try NativePrintConfiguration(values)
        let result = try await PrintRequestWait(driver: makeDriver(configuration), deadline: deadline, now: now).run()
        try Task.checkCancellation()
        return result
    }
}

@MainActor private final class SheetPrintDriver: NSObject, NativePrintDriver {
    let window: NSWindow
    let operation: NSPrintOperation
    var onFinish: ((Result<Bool, Error>) -> Void)?
    private weak var ownedSheet: NSWindow?
    private var retention: SheetPrintDriver?
    init(_ configuration: NativePrintConfiguration) throws {
        guard let window = NSApp?.keyWindow else { throw DraftlyError.message("Open a Draftly window before printing.") }
        guard window.attachedSheet == nil else { throw DraftlyError.message("Close the current window sheet before printing.") }
        self.window = window
        operation = try NativePrintLayout.makeOperation(configuration, printInfo: .shared)
        super.init()
    }
    func start() {
        retention = self
        operation.runModal(for: window, delegate: self, didRun: #selector(Self.didRun(_:success:contextInfo:)), contextInfo: nil)
        ownedSheet = window.attachedSheet
    }
    func cancelOwnedPresentation() {
        guard let sheet = ownedSheet, window.attachedSheet === sheet else { return }
        ownedSheet = nil
        window.endSheet(sheet, returnCode: .cancel)
        sheet.orderOut(nil)
    }
    func detach() { onFinish = nil }
    @objc private func didRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        ownedSheet = nil
        // AppKit does not distinguish user cancellation from printing failure here.
        if let error = (operation.view as? NativePrintTextView)?.layoutError { onFinish?(.failure(error)) }
        else { onFinish?(.success(success)) }
        retention = nil
    }
}

@MainActor private final class PrintRequestWait {
    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }
    private let cancellation = CancellationState()
    let driver: any NativePrintDriver
    var continuation: CheckedContinuation<Bool, Error>?
    var timer: Task<Void, Never>?
    let deadline: Date
    let now: @MainActor () -> Date
    init(driver: any NativePrintDriver, deadline: Date, now: @escaping @MainActor () -> Date) {
        self.driver = driver; self.deadline = deadline; self.now = now
    }
    func run() async throws -> Bool {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError()), cancel: true); return }
                guard now() < deadline else { finish(.failure(ActionExecutionInterruption.timeout), cancel: true); return }
                driver.onFinish = { [weak self] result in self?.finish(result) }
                timer = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSince(now())))) } catch { return }
                    finish(.failure(ActionExecutionInterruption.timeout), cancel: true)
                }
                driver.start()
            }
        } onCancel: { [cancellation] in
            cancellation.cancel()
            Task { @MainActor in self.finish(.failure(CancellationError()), cancel: true) }
        }
    }
    private func finish(_ result: Result<Bool, Error>, cancel: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        let expired = !cancel && now() >= deadline
        timer?.cancel(); timer = nil
        driver.detach()
        let cancelled = cancellation.isCancelled
        if cancel || cancelled || expired { driver.cancelOwnedPresentation() }
        if cancelled { continuation.resume(throwing: CancellationError()) }
        else { continuation.resume(with: expired ? .failure(ActionExecutionInterruption.timeout) : result) }
    }
}
