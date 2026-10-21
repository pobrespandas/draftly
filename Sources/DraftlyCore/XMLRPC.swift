import Foundation
import CoreFoundation

public enum ScriptXMLRPC {
    static func requestValues(_ values: [String: Any]) throws -> [String: Any] {
        let body = try requestBody(method: values["methodName"] as? String ?? "", params: values["params"] as? [Any] ?? [])
        return ["url": values["url"] ?? "", "method": "POST", "headers": ["Content-Type": "text/xml; charset=utf-8"], "encoding": "raw", "data": body, "includeResponseBytes": true]
    }

    static func responseEnvelope(_ envelope: [String: Any]) throws -> [String: Any] {
        guard let value = envelope["value"] as? [String: Any] else {
            throw DraftlyError.message("The XML-RPC transport response has no value.")
        }
        guard value["success"] as? Bool == true else { return responseValue(value) }
        if let encoded = envelope["responseBodyBase64"] {
            guard let encoded = encoded as? String, let data = Data(base64Encoded: encoded) else {
                throw DraftlyError.message("The XML-RPC response body is not valid base64.")
            }
            return response(data, statusCode: value["statusCode"] as? Int ?? 0)
        }
        return responseValue(value)
    }

    static func responseValue(_ value: [String: Any]) -> [String: Any] {
        guard value["success"] as? Bool == true else {
            return ["success": false, "statusCode": value["statusCode"] ?? 0, "params": [], "error": value["error"] ?? "The XML-RPC HTTP request failed."]
        }
        // HTTP already decoded the bytes. Keep the declaration consistent with the new UTF-8 data.
        let text = (value["responseText"] as? String ?? "").replacingOccurrences(
            of: #"^(\uFEFF?<\?xml\s+[^?]*?\bencoding\s*=\s*)(["'])[^"']*\2"#,
            with: "$1\"UTF-8\"", options: .regularExpression)
        return response(Data(text.utf8), statusCode: value["statusCode"] as? Int ?? 0)
    }

    static func requestSerialized(_ payload: String,
        transport: @Sendable (String) async -> String = { await ScriptHTTP.requestSerialized($0) }) async -> String {
        let envelope: [String: Any]
        do {
            try Task.checkCancellation()
            guard let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
                throw DraftlyError.message("The XML-RPC request payload must be an object.")
            }
            let request = String(decoding: try JSONSerialization.data(withJSONObject: requestValues(values)), as: UTF8.self)
            let reply = await transport(request)
            try Task.checkCancellation()
            guard let response = try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any] else {
                throw DraftlyError.message("The XML-RPC transport response is invalid.")
            }
            if let error = response["error"] as? String { throw DraftlyError.message(error) }
            envelope = ["value": try responseEnvelope(response)]
        } catch { envelope = ["error": error.localizedDescription] }
        return (try? String(decoding: JSONSerialization.data(withJSONObject: envelope), as: UTF8.self))
            ?? "{\"error\":\"The XML-RPC response could not be serialized.\"}"
    }

    public static func requestBody(method: String, params: [Any]) throws -> String {
        "<?xml version=\"1.0\"?><methodCall><methodName>\(escape(method))</methodName><params>"
            + (try params.map { "<param>\(try encode($0))</param>" }.joined()) + "</params></methodCall>"
    }
    public static func response(_ data: Data, statusCode: Int) -> [String: Any] {
        do {
            let tree = Tree()
            let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = tree
            guard parser.parse(), let root = tree.root, root.name == "methodResponse", root.hasOnlyWhitespace else {
                throw DraftlyError.message("The XML-RPC response is invalid.")
            }
            guard root.children.count == 1,
                  let payload = root.children.first,
                  ["params", "fault"].contains(payload.name), payload.hasOnlyWhitespace else {
                throw DraftlyError.message("The XML-RPC response must contain either parameters or a fault.")
            }
            if payload.name == "fault" {
                guard payload.children.count == 1 else { throw DraftlyError.message("The XML-RPC fault is invalid.") }
            }
            if let fault = root.children.first(where: { $0.name == "fault" })?.children.first,
               let values = try decode(fault) as? [String: Any] {
                guard values.count == 2, let code = values["faultCode"] as? Int64,
                      let message = values["faultString"] as? String else {
                    throw DraftlyError.message("The XML-RPC fault fields are invalid.")
                }
                return ["success": false, "statusCode": statusCode, "params": [], "faultCode": code, "error": message]
            }
            guard let params = root.children.first(where: { $0.name == "params" }) else { throw DraftlyError.message("The XML-RPC response has no parameters.") }
            let values = try params.children.map { node -> Any in
                guard node.name == "param", node.hasOnlyWhitespace, node.children.count == 1, let value = node.children.first, value.name == "value" else { throw DraftlyError.message("An XML-RPC parameter is invalid.") }
                return try decode(value)
            }
            return ["success": statusCode == 200, "statusCode": statusCode, "params": values]
        } catch { return ["success": false, "statusCode": statusCode, "params": [], "error": error.localizedDescription] }
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func encode(_ value: Any, depth: Int = 0) throws -> String {
        guard depth < 64 else { throw DraftlyError.message("XML-RPC parameters are nested too deeply.") }
        let inner: String
        switch value {
        case is NSNull: inner = "<nil/>"
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { inner = "<boolean>\(number.boolValue ? 1 : 0)</boolean>" }
            else if CFNumberIsFloatType(number) { inner = "<double>\(number.doubleValue)</double>" }
            else { inner = "<i8>\(number.int64Value)</i8>" }
        case let string as String: inner = "<string>\(escape(string))</string>"
        case let date as Date: inner = "<dateTime.iso8601>\(APIValues.date(date))</dateTime.iso8601>"
        case let data as Data: inner = "<base64>\(data.base64EncodedString())</base64>"
        case let values as [Any]: inner = "<array><data>" + (try values.map { try encode($0, depth: depth + 1) }.joined()) + "</data></array>"
        case let values as [String: Any]: inner = "<struct>" + (try values.keys.sorted().map { "<member><name>\(escape($0))</name>\(try encode(values[$0]!, depth: depth + 1))</member>" }.joined()) + "</struct>"
        default: throw DraftlyError.message("An XML-RPC parameter has an unsupported type.")
        }
        return "<value>\(inner)</value>"
    }
    private static func decode(_ node: Node) throws -> Any {
        guard node.name == "value", node.children.count <= 1 else { throw DraftlyError.message("An XML-RPC value is invalid.") }
        guard let child = node.children.first else { return node.text }
        guard node.hasOnlyWhitespace else { throw DraftlyError.message("An XML-RPC value has mixed content.") }
        if !["array", "struct"].contains(child.name), !child.children.isEmpty {
            throw DraftlyError.message("An XML-RPC scalar contains nested elements.")
        }
        switch child.name {
        case "string", "dateTime.iso8601", "base64": return child.text
        case "int", "i4", "i8":
            guard let value = Int64(child.text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw DraftlyError.message("An XML-RPC integer is invalid.") }; return value
        case "double":
            guard let value = Double(child.text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { throw DraftlyError.message("An XML-RPC number is invalid.") }; return value
        case "boolean":
            guard ["0", "1"].contains(child.text) else { throw DraftlyError.message("An XML-RPC boolean is invalid.") }; return child.text == "1"
        case "nil":
            guard child.hasOnlyWhitespace else { throw DraftlyError.message("An XML-RPC nil value contains text.") }
            return NSNull()
        case "array":
            guard child.hasOnlyWhitespace, child.children.count == 1,
                  let data = child.children.first, data.name == "data", data.hasOnlyWhitespace else {
                throw DraftlyError.message("An XML-RPC array must contain one data element.")
            }
            return try data.children.map(decode)
        case "struct":
            guard child.hasOnlyWhitespace else { throw DraftlyError.message("An XML-RPC struct contains text.") }
            var values: [String: Any] = [:]
            for member in child.children {
                guard member.name == "member", member.hasOnlyWhitespace, member.children.count == 2,
                      let name = member.children.first(where: { $0.name == "name" }), name.children.isEmpty,
                      let value = member.children.first(where: { $0.name == "value" }) else {
                    throw DraftlyError.message("An XML-RPC member must contain one name and one value.")
                }
                values[name.text] = try decode(value)
            }
            return values
        default: throw DraftlyError.message("The XML-RPC value type \(child.name) is unavailable.")
        }
    }
    private final class Node {
        let name: String
        var text = ""
        var children: [Node] = []
        var hasOnlyWhitespace: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        init(_ name: String) { self.name = name }
    }
    private final class Tree: NSObject, XMLParserDelegate {
        var root: Node?
        var stack: [Node] = []
        var count = 0
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            count += 1
            guard stack.count < 64, count < 100_000 else { parser.abortParsing(); return }
            let node = Node(name)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
    }
}
