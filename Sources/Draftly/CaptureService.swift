import AppKit

enum CaptureServiceError: LocalizedError, Equatable {
    case unavailableSelection
    case unsupportedSelection
    case emptySelection
    case unreadableSelection(String)

    var errorDescription: String? {
        switch self {
        case .unavailableSelection: "No selected text is available."
        case .unsupportedSelection: "The selection does not contain a supported text format."
        case .emptySelection: "The selected text is empty."
        case .unreadableSelection(let format): "The selected \(format) could not be read."
        }
    }
}

@MainActor
protocol CaptureSelectionReading {
    var types: [NSPasteboard.PasteboardType]? { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
}

extension NSPasteboard: CaptureSelectionReading {}

@MainActor
final class CaptureService {
    enum Mode { case direct, options }

    private let save: (String) throws -> Void
    private let showOptions: (String) throws -> Void

    init(save: @escaping (String) throws -> Void,
         showOptions: @escaping (String) throws -> Void) {
        self.save = save
        self.showOptions = showOptions
    }

    func handle(_ pasteboard: NSPasteboard, mode: Mode) throws {
        let text = try Self.selectedText(from: pasteboard)
        switch mode {
        case .direct: try save(text)
        case .options: try showOptions(text)
        }
    }

    static func selectedText(from source: any CaptureSelectionReading) throws -> String {
        guard let types = source.types, !types.isEmpty else {
            throw CaptureServiceError.unavailableSelection
        }
        let supported: [(NSPasteboard.PasteboardType, NSPasteboard.PasteboardType)] = [
            (.string, .string), (.init("NSStringPboardType"), .string),
            (.rtf, .rtf), (.init("NSRTFPboardType"), .rtf),
            (.rtfd, .rtfd), (.init("NSRTFDPboardType"), .rtfd),
            (.URL, .URL), (.init("NSURLPboardType"), .URL), (.fileURL, .fileURL)
        ]
        guard let (type, format) = supported.first(where: { types.contains($0.0) }) else {
            throw CaptureServiceError.unsupportedSelection
        }
        let text: String
        switch format {
        case .string:
            guard let value = source.string(forType: type) else {
                throw CaptureServiceError.unreadableSelection("text")
            }
            text = value
        case .rtf, .rtfd:
            guard let data = source.data(forType: type) else {
                throw CaptureServiceError.unreadableSelection(format == .rtf ? "RTF" : "RTFD")
            }
            do {
                text = try NSAttributedString(
                    data: data,
                    options: [.documentType: format == .rtf ? NSAttributedString.DocumentType.rtf : .rtfd],
                    documentAttributes: nil
                ).string
            } catch {
                throw CaptureServiceError.unreadableSelection(format == .rtf ? "RTF" : "RTFD")
            }
        default:
            guard let value = source.string(forType: type) else {
                throw CaptureServiceError.unreadableSelection("URL")
            }
            try requireContent(value)
            guard let url = URL(string: value), let scheme = url.scheme, !scheme.isEmpty else {
                throw CaptureServiceError.unreadableSelection("URL")
            }
            text = url.absoluteString
        }
        try requireContent(text)
        return text
    }

    private static func requireContent(_ text: String) throws {
        guard !text.isEmpty else {
            throw CaptureServiceError.emptySelection
        }
    }
}
