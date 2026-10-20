import AppKit
import DraftlyCore

struct EventDialogValues: Sendable, Equatable {
    var title: String
    var notes: String
    var start: Date
    var end: Date

    func validate() throws {
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite, end >= start else {
            throw DraftlyError.message("The event end date precedes its start date or is invalid.")
        }
    }
}

@MainActor
enum EventDialogCommit {
    static func run(_ initial: EventDialogValues, present: NativeEventDialog.Presenter,
                    save: (EventDialogValues) throws -> Void) async throws -> EventDialogValues? {
        try Task.checkCancellation()
        try initial.validate()
        let response = try await present(initial)
        try Task.checkCancellation()
        guard let edited = response else { return nil }
        try edited.validate()
        try save(edited)
        return edited
    }
}

@MainActor
final class NativeEventDialog: NSObject, NSWindowDelegate {
    typealias Presenter = @MainActor (EventDialogValues) async throws -> EventDialogValues?
    private var continuation: CheckedContinuation<EventDialogValues?, Error>?
    private var panel: EventPanel?
    private let initial: EventDialogValues
    private let heading: String
    private var titleField: NSTextField?
    private var notesField: NSTextField?
    private var startPicker: NSDatePicker?
    private var endPicker: NSDatePicker?

    private init(_ initial: EventDialogValues, heading: String) {
        self.initial = initial
        self.heading = heading
    }

    static func present(_ values: EventDialogValues) async throws -> EventDialogValues? {
        try await NativeEventDialog(values, heading: "Edit calendar event").show()
    }

    static func presentCreation(_ values: EventDialogValues) async throws -> EventDialogValues? {
        try await NativeEventDialog(values, heading: "Create calendar event").show()
    }

    private func show() async throws -> EventDialogValues? {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError())); return }
                buildPanel()
            }
        } onCancel: {
            Task { @MainActor [self] in finish(.failure(CancellationError())) }
        }
    }

    private func buildPanel() {
        let panel = EventPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 310),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.panel = panel
        panel.title = heading
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.cancel = { [weak self] in self?.finish(.success(nil)) }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let title = NSTextField(string: initial.title), notes = NSTextField(string: initial.notes)
        let start = NSDatePicker(), end = NSDatePicker()
        for (picker, value) in [(start, initial.start), (end, initial.end)] {
            picker.datePickerElements = [.yearMonthDay, .hourMinute]
            picker.dateValue = value
        }
        titleField = title; notesField = notes; startPicker = start; endPicker = end
        for (label, field) in [("Title", title as NSView), ("Notes", notes as NSView),
                               ("Start", start as NSView), ("End", end as NSView)] {
            stack.addArrangedSubview(NSTextField(labelWithString: label))
            stack.addArrangedSubview(field)
            field.widthAnchor.constraint(equalToConstant: 360).isActive = true
        }
        let buttons = NSStackView()
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save Event", target: self, action: #selector(savePressed))
        save.keyEquivalent = "\r"
        buttons.addArrangedSubview(cancel); buttons.addArrangedSubview(save)
        stack.addArrangedSubview(buttons)
        guard let content = panel.contentView else { finish(.success(nil)); return }
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            content.bottomAnchor.constraint(greaterThanOrEqualTo: stack.bottomAnchor, constant: 20)
        ])
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(title)
    }

    @objc private func cancelPressed() { finish(.success(nil)) }
    @objc private func savePressed() {
        guard let titleField, let notesField, let startPicker, let endPicker else { return }
        finish(.success(EventDialogValues(title: titleField.stringValue, notes: notesField.stringValue,
                                          start: startPicker.dateValue, end: endPicker.dateValue)))
    }
    func windowWillClose(_ notification: Notification) { finish(.success(nil)) }

    private func finish(_ result: Result<EventDialogValues?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        panel?.delegate = nil
        panel?.cancel = nil
        panel?.close()
        panel = nil
        continuation.resume(with: result)
    }
}

@MainActor private final class EventPanel: NSPanel {
    var cancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { cancel?() }
}
