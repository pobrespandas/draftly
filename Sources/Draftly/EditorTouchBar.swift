import AppKit
import Combine
import DraftlyCore

@MainActor final class EditorTouchBarController: NSObject, NSTouchBarDelegate {
    static let customizationIdentifier = NSTouchBar.CustomizationIdentifier("draftly.editor")
    weak var model: WindowModel?
    weak var responder: NSResponder?
    private var subscriptions: [AnyCancellable] = []
    private var actionButtons: [UUID: NSButton] = [:]
    var invalidate: (() -> Void)?

    init(model: WindowModel, responder: NSResponder) {
        self.model = model; self.responder = responder
        super.init()
        model.$actionBarGroup.dropFirst().removeDuplicates().sink { [weak self] _ in self?.scheduleInvalidation() }.store(in: &subscriptions)
        model.library.$actions.dropFirst().sink { [weak self] _ in self?.scheduleInvalidation() }.store(in: &subscriptions)
        model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.updateEnabledState() }
        }.store(in: &subscriptions)
    }

    private func scheduleInvalidation() {
        DispatchQueue.main.async { [weak self] in self?.invalidate?() }
    }
    private func updateEnabledState() {
        guard let model else { return }
        for button in actionButtons.values { button.isEnabled = model.canRunActions }
    }
    static func identifier(for command: EditorBarCommand) -> NSTouchBarItem.Identifier {
        NSTouchBarItem.Identifier("draftly.editor.command." + command.rawValue)
    }
    static func identifier(for action: DraftAction) -> NSTouchBarItem.Identifier {
        NSTouchBarItem.Identifier("draftly.editor.action." + action.id.uuidString)
    }
    private var entries: [ActionCatalogPresentation.Entry] {
        guard let model else { return [] }
        return ActionCatalogPresentation.entries(model.library.orderedActions(), on: .bar, group: model.actionBarGroup)
    }
    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = Self.customizationIdentifier
        let commands = model?.actionBarGroup == "Editing" ? EditorBarCommand.allCases.map(Self.identifier(for:)) : []
        let actions = entries.map { Self.identifier(for: $0.source) }
        bar.defaultItemIdentifiers = commands + actions
        bar.customizationAllowedItemIdentifiers = bar.defaultItemIdentifiers
        actionButtons = [:]
        return bar
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let model else { return nil }
        if model.actionBarGroup == "Editing", let command = EditorBarCommand.allCases.first(where: { Self.identifier(for: $0) == identifier }) {
            let button = NSButton(image: NSImage(systemSymbolName: command.symbol, accessibilityDescription: command.title) ?? NSImage(), target: self, action: #selector(runCommand(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(command.rawValue)
            button.toolTip = command.title; button.setAccessibilityLabel(command.title)
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.customizationLabel = command.title; item.view = button
            return item
        }
        guard let entry = entries.first(where: { Self.identifier(for: $0.source) == identifier }) else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = entry.source.name
        if entry.kind == .separator {
            let separator = NSBox(); separator.boxType = .separator
            item.view = separator
        } else {
            let action = entry.source, label = ActionBarLabel(action)
            let button: NSButton
            if label.usesIcon, let image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.name) {
                button = NSButton(image: image, target: self, action: #selector(runAction(_:)))
            } else {
                button = NSButton(title: label.text, target: self, action: #selector(runAction(_:)))
            }
            button.identifier = NSUserInterfaceItemIdentifier(action.id.uuidString)
            button.toolTip = action.name; button.setAccessibilityLabel(action.name)
            button.isEnabled = model.canRunActions
            actionButtons[action.id] = button
            item.view = button
        }
        return item
    }
    @objc private func runCommand(_ button: NSButton) {
        guard let model, let raw = button.identifier?.rawValue, let command = EditorBarCommand(rawValue: raw) else { return }
        command.perform(model: model, session: model.editor, responder: responder)
    }
    @objc private func runAction(_ button: NSButton) {
        guard let model, model.canRunActions, let id = (button.identifier?.rawValue).flatMap(UUID.init(uuidString:)),
              let action = entries.compactMap(\.runnableAction).first(where: { $0.id == id }) else { return }
        model.run(action)
    }
}
