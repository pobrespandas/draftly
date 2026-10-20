import SwiftUI
import AppKit
import DraftlyCore

struct SettingsView: View {
    @AppStorage("editor.fontName") private var fontName = "System"
    @AppStorage("editor.fontSize") private var fontSize = 17.0
    @AppStorage("editor.lineSpacing") private var lineSpacing = 2.0
    @AppStorage("capture.newDraftAfter") private var newDraftAfter = 300.0
    private var nerdFontOptions: [(family: String, postScriptName: String)] {
        NSFontManager.shared.availableFontFamilies
            .filter { $0.localizedCaseInsensitiveContains("Nerd Font") }
            .sorted()
            .compactMap { family in
                guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                      let regular = members.first(where: { ($0[1] as? String) == "Regular" }),
                      let postScriptName = regular[0] as? String else { return nil }
                return (family, postScriptName)
            }
    }
    var body: some View {
        Form {
            Section("Editor") {
                Picker("Font", selection: $fontName) {
                    Text("System").tag("System")
                    Text("SF Mono").tag("SFMono-Regular")
                    Text("Menlo").tag("Menlo-Regular")
                    Text("Helvetica Neue").tag("HelveticaNeue")
                    if !nerdFontOptions.isEmpty {
                        Divider()
                        ForEach(nerdFontOptions, id: \.postScriptName) { option in
                            Text(option.family).tag(option.postScriptName)
                        }
                    }
                }
                HStack { Text("Size"); Slider(value: $fontSize, in: 11...28, step: 1); Text("\(Int(fontSize)) pt").monospacedDigit() }
                HStack { Text("Line spacing"); Slider(value: $lineSpacing, in: 0...16, step: 1); Text("\(Int(lineSpacing)) pt").monospacedDigit() }
            }
            EditorLayoutPreferences()
            ShortcutPreferences()
            Section("Capture") {
                LabeledContent("Global shortcut", value: AppController.shared.captureShortcutStatus)
                Picker("New Draft After", selection: $newDraftAfter) {
                    Text("Never").tag(0.0); Text("30 seconds").tag(30.0); Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0); Text("15 minutes").tag(900.0); Text("1 hour").tag(3600.0)
                }
            }
            Section("Data") {
                if let library = AppController.shared.library { LibrarySyncStatusView(library: library) }
                else { Text("Library unavailable").font(.caption) }
                Button("Show Library Folder") {
                    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draftly")
                    NSWorkspace.shared.open(folder)
                }
                Text("Use File → Export Full Backup to save drafts, revisions, workspaces, and actions.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 500, height: 440)
    }
}

struct LibrarySyncStatusView: View {
    @ObservedObject var library: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(library.syncStatus).font(.caption).textSelection(.enabled)
            if library.cloudIdentifier != nil {
                Button("Check iCloud Account") { Task { await library.refreshCloudAccount() } }
                Text("Local saves do not confirm that other Macs received your changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
