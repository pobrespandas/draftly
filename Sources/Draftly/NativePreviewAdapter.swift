import AppKit
import WebKit
import DraftlyCore

@MainActor
final class NativePreviewAdapter {
    private var previewWindows: [NSWindow] = []
    static let operations: Set<String> = ["htmlToClipboard", "markdown", "previewMarkdown", "htmlPreview", "share", "shareFile"]

    func perform(_ operation: String, values: [String: Any], host: NativeActionHost) throws -> Any? {
        let text = values["text"] as? String ?? ""
        switch operation {
        case "htmlToClipboard":
            guard let data = (values["html"] as? String)?.data(using: .utf8) else { return false }
            let rich = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
            let rtf = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(rtf, forType: .rtf)
            NSPasteboard.general.setData(data, forType: .html)
            NSPasteboard.general.setString(rich.string, forType: .string)
            return true
        case "markdown": return try MarkdownPreferences.render(text)
        case "previewMarkdown": host.showHTML(MarkdownRenderer.page(try MarkdownPreferences.render(text))); return true
        case "htmlPreview": return host.interactivePreview(values)
        case "share", "shareFile":
            let item: Any
            if operation == "shareFile" {
                let name = (values["name"] as? String ?? "Draft.txt").replacingOccurrences(of: "/", with: "-")
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(name); try text.write(to: url, atomically: true, encoding: .utf8); item = url
            } else { item = text }
            guard let view = NSApp.keyWindow?.contentView else { throw DraftlyError.message("Open a Draftly window before sharing.") }
            NSSharingServicePicker(items: [item]).show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 20, width: 1, height: 1), of: view, preferredEdge: .minY)
            return true
        default: throw DraftlyError.message("The native operation is unavailable.")
        }
    }

    func showHTML(_ html: String, onPreview: ((String) -> Void)?) {
        if let onPreview { onPreview(html); return }
        let config = WKWebViewConfiguration(); config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 680), configuration: config)
        view.loadHTMLString(html, baseURL: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Preview — Draftly"; window.contentView = view; window.isReleasedWhenClosed = false
        window.center(); window.makeKeyAndOrderFront(nil)
        previewWindows.removeAll { !$0.isVisible }; previewWindows.append(window)
    }
}
