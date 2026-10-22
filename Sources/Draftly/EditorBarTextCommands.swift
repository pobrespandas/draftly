import Foundation

struct EditorBarTextChange {
    let content: String
    let selection: NSRange
}

// Callers must pass the session safe selection.
enum EditorBarTextCommands {
    static func move(in text: String, selection: NSRange, offset: Int) -> NSRange? {
        let source = text as NSString
        if offset < 0, selection.location > 0 {
            return NSRange(location: source.rangeOfComposedCharacterSequence(at: selection.location - 1).location, length: 0)
        } else if offset > 0, NSMaxRange(selection) < source.length {
            return NSRange(location: NSMaxRange(source.rangeOfComposedCharacterSequence(at: NSMaxRange(selection))), length: 0)
        }
        return nil
    }

    static func moveLine(in text: String, selection: NSRange, direction: Int) -> EditorBarTextChange? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        let block = source.lineRange(for: selection)
        if direction < 0 {
            guard block.location > 0 else { return nil }
            let previous = source.lineRange(for: NSRange(location: block.location - 1, length: 0))
            let replacement = source.substring(with: previous) + source.substring(with: block)
            return EditorBarTextChange(
                content: source.replacingCharacters(in: NSRange(location: previous.location, length: NSMaxRange(block) - previous.location), with: replacement),
                selection: NSRange(location: max(0, selection.location - previous.length), length: selection.length))
        } else {
            guard NSMaxRange(block) < source.length else { return nil }
            let next = source.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            let replacement = source.substring(with: next) + source.substring(with: block)
            return EditorBarTextChange(
                content: source.replacingCharacters(in: NSRange(location: block.location, length: NSMaxRange(next) - block.location), with: replacement),
                selection: NSRange(location: selection.location + next.length, length: selection.length))
        }
    }

    static func duplicateLine(in text: String, selection: NSRange) -> EditorBarTextChange? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        let line = source.lineRange(for: selection)
        let duplicate = source.substring(with: line)
        let insertion = NSMaxRange(line)
        return EditorBarTextChange(
            content: source.replacingCharacters(in: NSRange(location: insertion, length: 0), with: duplicate),
            selection: NSRange(location: insertion, length: (duplicate as NSString).length))
    }

    static func marker(in ranges: [NSRange], selection: NSRange, direction: Int) -> NSRange? {
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return direction < 0
            ? (ranges.last { $0.location < selection.location } ?? last)
            : (ranges.first { $0.location > selection.location } ?? first)
    }
}
