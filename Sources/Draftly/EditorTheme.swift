import AppKit

struct EditorTheme: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "New Theme"
    var foreground = "202020"
    var background = "FFFFFF"
    var heading = "007AFF"
    var isDark = false
    static func selected(name: String, data: String) -> EditorTheme? {
        (try? JSONDecoder().decode([EditorTheme].self, from: Data(data.utf8)))?.first { $0.name == name }
    }
    static func color(_ text: String) -> NSColor? {
        let value = text.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((number >> 16) & 255) / 255, green: CGFloat((number >> 8) & 255) / 255, blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}
