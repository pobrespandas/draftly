import Foundation
import CloudKit

/// Tracks operations. A completed export does not prove that other Macs received it.
struct CloudSyncState: Equatable {
    enum Phase: String, Hashable { case setup, download, upload }
    enum Account: Equatable {
        case checking, available, signedOut, restricted, temporarilyUnavailable
        case failed(String)
    }
    var account: Account = .checking
    private(set) var active: [UUID: Phase] = [:]
    private(set) var failures: [Phase: String] = [:]
    private(set) var lastCompletion: Phase?

    mutating func receive(id: UUID, phase: Phase, ended: Bool, succeeded: Bool, error: String?) {
        if !ended { active[id] = phase; return }
        active.removeValue(forKey: id)
        if succeeded && error == nil {
            failures[phase] = nil
            lastCompletion = phase
        } else {
            failures[phase] = error ?? "The operation did not complete."
        }
    }

    var message: String {
        switch account {
        case .checking: return "Checking iCloud account…"
        case .signedOut: return "iCloud unavailable · Sign in to iCloud in System Settings. Local changes remain on this Mac."
        case .restricted: return "iCloud access is restricted. Local changes remain on this Mac."
        case .temporarilyUnavailable: return "iCloud account is temporarily unavailable. Local changes remain on this Mac."
        case .failed(let error): return "iCloud account: \(error)"
        case .available: break
        }
        for phase in [Phase.setup, .upload, .download] {
            if let error = failures[phase] { return "iCloud \(phase.rawValue): \(error)" }
        }
        if !active.isEmpty { return "Syncing with iCloud… Changes may still be pending." }
        switch lastCompletion {
        case .upload: return "Last iCloud upload completed. Other Macs may still be syncing."
        case .download: return "Last iCloud download completed. Changes may still be pending."
        case .setup, nil: return "iCloud connected · Waiting for sync operations."
        }
    }
}

/// Shows nested CloudKit failures without record identifiers or payloads.
enum CloudSyncError {
    static func message(_ error: Error) -> String {
        var messages: [String] = []
        func visit(_ error: Error, depth: Int) {
            guard depth < 4 else { return }
            let value = error as NSError
            let text: String
            if value.domain == CKErrorDomain && value.userInfo[NSLocalizedDescriptionKey] == nil {
                switch value.code {
                case CKError.partialFailure.rawValue:
                    text = "Some iCloud operations failed. Check account access and the app/container configuration."
                case CKError.permissionFailure.rawValue:
                    text = "iCloud permission was denied. Check the app/container assignment in Apple Developer."
                case CKError.notAuthenticated.rawValue:
                    text = "Sign in to iCloud in System Settings."
                case CKError.networkUnavailable.rawValue, CKError.networkFailure.rawValue:
                    text = "The iCloud connection is unavailable. Local changes remain on this Mac."
                default: text = value.localizedDescription
                }
            } else { text = value.localizedDescription }
            if !messages.contains(text) { messages.append(text) }
            if let partial = value.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                for item in partial.values.prefix(3) { visit(item, depth: depth + 1) }
            }
            if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error { visit(underlying, depth: depth + 1) }
        }
        visit(error, depth: 0)
        return messages.joined(separator: " · ")
    }
}
