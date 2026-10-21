import DraftlyCore

enum ThemePickerOptions {
    struct Option: Identifiable, Equatable {
        let id: String
        let title: String
        let reference: [String: String]

        var editorTag: String { (reference["type"] ?? "builtIn") + ":" + id }
    }

    static func values(themes: [EditorTheme]) -> [Option] {
        ThemeCatalog.builtInNames.map { Option(id: $0, title: $0, reference: ["name": $0]) }
            + themes.map { Option(id: $0.id.uuidString,
                title: $0.name + ($0.type == "file" ? " (File)" : ""),
                reference: ["name": $0.name, "uuid": $0.id.uuidString, "type": $0.type]) }
    }
}
