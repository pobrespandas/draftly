import Foundation

extension SyntaxDefinition {
    /// Plans one editor replacement without changing the input text.
    @_spi(EditorImplementation)
    public func orderedListEdit(in source: String, replacing range: NSRange, with inserted: String) throws
        -> (range: NSRange, text: String, selection: NSRange)? {
        let original = source as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= original.length, range.length <= original.length - range.location else { return nil }
        let proposed = original.replacingCharacters(in: range, with: inserted)
        let insertedRange = NSRange(location: range.location, length: inserted.utf16.count)
        let edits = try orderedListRenumbering(in: proposed, affectedRange: insertedRange)
        guard !edits.isEmpty else {
            return (range, inserted, NSRange(location: NSMaxRange(insertedRange), length: 0))
        }
        var cursor = NSMaxRange(insertedRange)
        var shift = 0
        for edit in edits {
            let start = edit.range.location + shift
            let end = start + edit.range.length
            let replacementLength = edit.text.utf16.count
            if cursor >= end { cursor += replacementLength - edit.range.length }
            else if cursor > start { cursor = start + min(cursor - start, replacementLength) }
            shift += replacementLength - edit.range.length
        }
        let result = NSMutableString(string: proposed)
        for edit in edits.reversed() { result.replaceCharacters(in: edit.range, with: edit.text) }
        // Map each sequence edit back through the original replacement.
        func originalPosition(_ position: Int, upper: Bool) -> Int {
            if position <= insertedRange.location { return position }
            if position >= NSMaxRange(insertedRange) { return position - insertedRange.length + range.length }
            return upper ? NSMaxRange(range) : range.location
        }
        var start = range.location, end = NSMaxRange(range)
        for edit in edits {
            start = min(start, originalPosition(edit.range.location, upper: false))
            end = max(end, originalPosition(NSMaxRange(edit.range), upper: true))
        }
        let suffix = original.length - end
        let replacement = result.substring(with: NSRange(location: start, length: result.length - start - suffix))
        return (NSRange(location: start, length: end - start), replacement,
                NSRange(location: cursor, length: 0))
    }
}
