import Compression
import Foundation

/// Reads the zlib-wrapped JSON used by Drafts action group exports.
enum DraftsActionGroupImport {
    private static let maximumBytes = 16 * 1024 * 1024

    static func decode(_ data: Data) throws -> (ActionGroupRecord, [DraftAction]) {
        try decodeJSON(decompress(data))
    }

    static func decodeJSON(_ json: Data) throws -> (ActionGroupRecord, [DraftAction]) {
        guard case .object(var fields) = try JSONDecoder().decode(JSONValue.self, from: json),
              case .string(let name) = fields["name"], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .string(let uuid) = fields["uuid"], let id = UUID(uuidString: uuid),
              case .array(let entries) = fields["actions"] else {
            throw DraftlyError.message("The action group export is invalid.")
        }
        let actionData = try JSONEncoder().encode(JSONValue.array(entries))
        var actions = try ActionImporter.decode(actionData)
        for index in actions.indices {
            actions[index].group = name
            var options = actions[index].options ?? ActionPresentation()
            options.order = index
            actions[index].options = options
        }
        var group = ActionGroupRecord(name: name); group.id = id
        if fields["icon"] == .string("action_circle2") {
            group.symbol = "circle.circle"
        } else if case .string(let icon) = fields["icon"], icon.hasPrefix("symbol||"), icon.count > 8 {
            group.symbol = String(icon.dropFirst(8))
        }
        fields.removeValue(forKey: "actions")
        group.importedMetadata = fields
        return (group, actions)
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 6, bytes.count <= maximumBytes,
              bytes[0] & 0x0f == 8, bytes[0] >> 4 <= 7,
              (Int(bytes[0]) * 256 + Int(bytes[1])) % 31 == 0,
              bytes[1] & 0x20 == 0 else {
            throw DraftlyError.message("The action group compression header is invalid.")
        }
        let placeholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { placeholder.deallocate() }
        var stream = compression_stream(dst_ptr: placeholder, dst_size: 0, src_ptr: UnsafePointer(placeholder), src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            throw DraftlyError.message("The action group could not be decompressed.")
        }
        defer { compression_stream_destroy(&stream) }
        var output = Data()
        let status: compression_status = bytes.withUnsafeBytes { input in
            stream.src_ptr = input.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: 2)
            stream.src_size = bytes.count - 6
            var buffer = [UInt8](repeating: 0, count: 65536)
            return buffer.withUnsafeMutableBytes { destination in
                while true {
                    stream.dst_ptr = destination.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    stream.dst_size = destination.count
                    let result = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    let produced = destination.count - stream.dst_size
                    guard output.count <= maximumBytes - produced else { return COMPRESSION_STATUS_ERROR }
                    output.append(destination.baseAddress!.assumingMemoryBound(to: UInt8.self), count: produced)
                    if result != COMPRESSION_STATUS_OK { return result }
                    if produced == 0 { return COMPRESSION_STATUS_ERROR }
                }
            }
        }
        guard status == COMPRESSION_STATUS_END, stream.src_size == 0 else {
            throw DraftlyError.message("The action group is invalid or exceeds the size limit.")
        }
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in output { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let expected = bytes.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard (b << 16 | a) == expected else { throw DraftlyError.message("The action group checksum is invalid.") }
        return output
    }
}
