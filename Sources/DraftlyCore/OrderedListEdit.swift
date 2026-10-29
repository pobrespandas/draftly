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
        let final = result as String
        var prefix = 0
        var left = source.startIndex, right = final.startIndex
        while left < source.endIndex, right < final.endIndex,
              String(source[left]).utf8.elementsEqual(String(final[right]).utf8) {
            prefix += String(source[left]).utf16.count
            source.formIndex(after: &left); final.formIndex(after: &right)
        }
        var oldEnd = source.endIndex, newEnd = final.endIndex
        var suffix = 0
        while oldEnd > left, newEnd > right {
            let previousOld = source.index(before: oldEnd), previousNew = final.index(before: newEnd)
            guard String(source[previousOld]).utf8.elementsEqual(String(final[previousNew]).utf8) else { break }
            suffix += String(source[previousOld]).utf16.count
            oldEnd = previousOld; newEnd = previousNew
        }
        let replacement = (final as NSString).substring(with: NSRange(location: prefix, length: final.utf16.count - prefix - suffix))
        return (NSRange(location: prefix, length: original.length - prefix - suffix), replacement,
                NSRange(location: cursor, length: 0))
    }
}
