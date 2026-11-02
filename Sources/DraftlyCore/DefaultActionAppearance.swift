import Foundation

public enum DefaultActionAppearance {
    public static func applying(to source: DraftAction) -> DraftAction {
        var action = source
        if source.presentation.barLabel == nil {
            action.presentation.barLabel = ["Insert Dictation": "Insert", "Dictate New Draft": "New", "Paste as Plain Text": "Paste", "Save Version": "Version"][source.name]
        }
        let symbols: [String: String] = [
            "Mail": "envelope.fill", "Message": "message.fill", "Google Search": "doc.text.magnifyingglass",
            "List in Reminders": "checklist", "Save to Files": "rectangle.portrait.and.arrow.right",
            "Save to Files as...": "rectangle.portrait.and.arrow.right", "Save to iCloud Drive": "icloud",
            "Append to iCloud Journal": "book.closed.fill", "Save to OneDrive": "cloud.fill",
            "Append to OneDrive Journal": "cloud.fill", "Move Left": "chevron.left", "Move Right": "chevron.right",
            "Move Back by Word": "chevron.left.2", "Move Forward by Word": "chevron.right.2",
            "Advanced Find": "plus.magnifyingglass", "Toggle Tasks": "checklist",
            "Markdown Footnote (^)": "chevron.up", "Inline Code (`)": "command", "Code Block (```)": "command",
            "Quote-Increase (>)": "chevron.right", "Quote-Decrease": "chevron.left",
            "UPPER": "arrow.up.circle.fill", "lower": "arrow.down.circle.fill", "Title": "textformat",
            "Straighten Quotes": "textformat", "Strip Diacritics": "textformat",
            "Strip Line Feed": "chevron.left.circle.fill", "Strip Extra Blank Lines": "chevron.left.circle.fill",
            "Hard Wrap": "line.3.horizontal.circle", "Trim Whitespace": "minus.square.fill",
            "Smart Parentheses": "pencil.line", "Smart Brackets": "pencil.line", "Smart Braces": "pencil.line",
            "Encode...": "chevron.right.2", "Decode...": "chevron.left.2",
            "Update Tags...": "tag.fill", "Rename Tag...": "tag.fill", "Flag": "flag.fill",
            "Unflag": "flag.slash", "Apply Template": "doc.badge.plus",
            "Previous Placeholder <|>": "chevron.up", "Next Placeholder <|>": "chevron.down"
        ]
        if let symbol = symbols[source.name] { action.symbol = symbol }
        if source.presentation.tintColor == nil {
            let colors: [String: String] = [
                "Message": "green", "Google Search": "green", "Send to Reminders": "gray",
                "Save to Files": "orange", "Save to Files as...": "green", "Save to iCloud Drive": "green",
                "Append to iCloud Journal": "green", "Save to Google Drive": "red",
                "Append to Google Drive Journal": "green", "Save to OneDrive": "orange", "Append to OneDrive Journal": "orange",
                "Move Left": "yellow", "Move Right": "yellow", "Move Back by Word": "orange",
                "Move Forward by Word": "orange", "Find": "green", "Toggle Tasks": "indigo",
                "Dictate New Draft": "green", "Indent": "orange", "Outdent": "orange",
                "Toggle Theme": "gray", "Inline Code (`)": "gray", "Markdown Footnote (^)": "gray",
                "Code Block (```)": "gray", "Markdown List": "yellow", "Markdown Table": "purple",
                "Edit Markdown Table": "indigo", "Preview": "gray", "Preview - RTL": "gray",
                "Copy as HTML": "gray", "Copy as Rich Text": "gray", "Copy as Rich Text w/o Styles": "gray",
                "Straighten Quotes": "yellow", "Strip Diacritics": "yellow", "Strip Line Feed": "indigo",
                "Hard Wrap": "indigo", "Strip Extra Blank Lines": "orange", "Trim Whitespace": "yellow",
                "Remove Blank Lines": "yellow", "Format Number": "yellow", "Archive": "gray", "Trash": "red",
                "Update Tags...": "orange", "Rename Tag...": "red", "Flag": "orange", "Unflag": "gray",
                "Select Workspace": "gray", "Filter by Tag": "gray", "New Draft in Workspace": "green",
                "Apply Template": "indigo", "Previous Placeholder <|>": "yellow", "Next Placeholder <|>": "yellow",
                "Inbox": "indigo"
            ]
            action.presentation.tintColor = colors[source.name] ?? "blue"
        }
        return action
    }
}
