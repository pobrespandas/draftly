import AppKit
import DraftlyCore

struct DraftRowPresentation {
    static let verticalInset: CGFloat = 7
    static let bottomInset: CGFloat = 6
    static let contentSpacing: CGFloat = 2
    static let titleHeight: CGFloat = 17
    static let tagHeight: CGFloat = 14
    static let tagTopInset: CGFloat = 5
    static let dateHeight: CGFloat = 13
    static let dateTopInset: CGFloat = 2
    static let titleSize: CGFloat = 14
    static let previewSize: CGFloat = 13
    static let previewLineHeight: CGFloat = 16
    static let tagSize: CGFloat = 10
    static let dateSize: CGFloat = 11

    static func preview(_ note: Note, query: String = "") -> String {
        let lines = note.content.components(separatedBy: .newlines)
        if !query.isEmpty {
            let matches = lines.enumerated().compactMap { index, line -> String? in
                guard line.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { return nil }
                return "\(index + 1): " + line.trimmingCharacters(in: .whitespaces)
            }
            if !matches.isEmpty { return matches.joined(separator: "\n") }
        }
        let text = lines.dropFirst().joined(separator: "\n")
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " • ")
    }

    static func height(note: Note, width: CGFloat, showPreview: Bool, previewLines: Int,
                       showTags: Bool, showDate: Bool, lastAction: Bool, query: String = "") -> CGFloat {
        var height = verticalInset + bottomInset + titleHeight
        let text = preview(note, query: query)
        if showPreview && !text.isEmpty {
            let measured = (text as NSString).boundingRect(with: NSSize(width: max(1, width), height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: previewSize, weight: query.isEmpty ? .regular : .semibold)]).height
            height += min(ceil(measured), CGFloat(min(3, max(1, previewLines))) * previewLineHeight) + contentSpacing
        }
        if showTags && !note.tags.isEmpty { height += tagHeight + tagTopInset + contentSpacing }
        if showDate { height += dateHeight + dateTopInset + contentSpacing }
        if lastAction { height += 18 }
        return height
    }

    static func modifiedDate(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        let day: String
        if calendar.isDateInToday(date) { day = "Today" }
        else if calendar.isDateInYesterday(date) { day = "Yesterday" }
        else if calendar.isDateInTomorrow(date) { day = "Tomorrow" }
        else { formatter.setLocalizedDateFormatFromTemplate("yyyyMMdd"); day = formatter.string(from: date) }
        formatter.dateFormat = "HH:mm"
        return day + ", " + formatter.string(from: date)
    }
}
