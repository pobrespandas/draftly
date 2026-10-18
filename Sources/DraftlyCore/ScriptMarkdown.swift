import Foundation
import CMultiMarkdown
import CGFM

public enum ScriptMarkdown {
    private static let lock = NSLock()
    public static func render(_ text: String, engine: String, options: [String: Any] = [:]) throws -> String {
        lock.lock(); defer { lock.unlock() }
        if engine == "multi" { return try multi(text, options: options) }
        return try github(text, options: options)
    }
    private static func multi(_ text: String, options: [String: Any]) throws -> String {
        var extensions: UInt = 0
        let settings: [(String, Int, Bool)] = [("markdownCompatibilityMode",0,false),("completeDocument",1,false),("snippetOnly",2,false),("smartQuotesEnabled",3,true),("footnotesEnabled",4,true),("noLabels",5,true),("processHTML",6,true),("noMetadata",7,false),("obfuscate",8,false),("criticMarkup",9,false),("criticMarkupAccept",10,false),("criticMarkupReject",11,false),("randomFootnotes",12,false)]
        for (key, bit, fallback) in settings where options[key] as? Bool ?? fallback { extensions |= UInt(1 << bit) }
        let formats: [String: Int16] = ["html":0,"latex":2,"beamer":3,"memoir":4,"odt":5,"fodt":5,"opml":9,"mmd":11]
        let name = options["format"] as? String ?? "html"
        guard let format = formats[name] else { throw DraftlyError.message("The MultiMarkdown format \(name) is not a text output format.") }
        guard let result = text.withCString({ mmd_string_convert($0, extensions, format, 0) }) else { throw DraftlyError.message("MultiMarkdown could not render the document.") }
        defer { free(result) }; return String(cString: result)
    }
    private static func github(_ text: String, options: [String: Any]) throws -> String {
        cmark_gfm_core_extensions_ensure_registered()
        var flags: Int32 = 0
        for (name, flag) in [("sourcePOS",CMARK_OPT_SOURCEPOS),("hardBreaks",CMARK_OPT_HARDBREAKS),("validateUTF8",CMARK_OPT_VALIDATE_UTF8),("smartQuotes",CMARK_OPT_SMART),("unsafe",CMARK_OPT_UNSAFE),("footnotes",CMARK_OPT_FOOTNOTES)] where options[name] as? Bool == true { flags |= flag }
        if options["smartQuotesEnabled"] as? Bool == true { flags |= CMARK_OPT_SMART }
        if options["safe"] as? Bool == true { flags &= ~CMARK_OPT_UNSAFE }
        guard let parser = cmark_parser_new(flags) else { throw DraftlyError.message("The GitHub Markdown parser could not start.") }
        defer { cmark_parser_free(parser) }
        for (name, key) in [("table","tables"),("strikethrough","strikethrough"),("autolink","autoLinks"),("tagfilter","tagFilters"),("tasklist","taskLists")] where options[key] as? Bool ?? true {
            if let ext = name.withCString({ cmark_find_syntax_extension($0) }) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        text.withCString { cmark_parser_feed(parser, $0, text.utf8.count) }
        guard let document = cmark_parser_finish(parser) else { throw DraftlyError.message("GitHub Markdown could not parse the document.") }
        defer { cmark_node_free(document) }
        if options["noImages"] as? Bool == true || options["noLinks"] as? Bool == true || options["removeHTMLTags"] as? Bool == true {
            var replacements: [(OpaquePointer, String)] = []
            if let iterator = cmark_iter_new(document) {
                while cmark_iter_next(iterator) != CMARK_EVENT_DONE {
                    guard cmark_iter_get_event_type(iterator) == CMARK_EVENT_ENTER, let node = cmark_iter_get_node(iterator) else { continue }
                    let type = cmark_node_get_type(node)
                    if type == CMARK_NODE_IMAGE && options["noImages"] as? Bool == true { replacements.append((node,"")) }
                    if type == CMARK_NODE_LINK && options["noLinks"] as? Bool == true {
                        var child = cmark_node_first_child(node), label = ""
                        while let current = child { if let literal = cmark_node_get_literal(current) { label += String(cString: literal) }; child = cmark_node_next(current) }
                        replacements.append((node,label))
                    }
                    if (type == CMARK_NODE_HTML_INLINE || type == CMARK_NODE_HTML_BLOCK) && options["removeHTMLTags"] as? Bool == true { replacements.append((node,"")) }
                }
                cmark_iter_free(iterator)
            }
            for (node, text) in replacements.reversed() {
                if let replacement = cmark_node_new(CMARK_NODE_TEXT) { text.withCString { _ = cmark_node_set_literal(replacement,$0) }; cmark_node_replace(node,replacement); cmark_node_free(node) }
            }
        }
        guard let result = cmark_render_html(document,flags,cmark_parser_get_syntax_extensions(parser)) else { throw DraftlyError.message("GitHub Markdown could not render the document.") }
        defer { free(result) }; return String(cString: result)
    }
}
