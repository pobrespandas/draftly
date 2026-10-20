import SwiftUI
import AppKit
import DraftlyCore

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @AppStorage("settings.selectedTab") private var selectedTab = "general"
    @AppStorage(ApplicationAppearance.preferenceKey) private var appearance = "System"
    @AppStorage(GeneralPreferences.showInMenuBarKey) private var showInMenuBar = true
    @AppStorage(GeneralPreferences.advancedFindKey) private var preferAdvancedFind = false
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
        TabView(selection: $selectedTab) {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            dataSettings
                .tabItem { Label("iCloud", systemImage: "icloud") }.tag("icloud")
            BookmarkSettingsView()
                .tabItem { Label("Bookmarks", systemImage: "bookmark") }.tag("bookmarks")
            MarkdownSettingsView()
                .tabItem { Label("Markdown", systemImage: "star.circle.fill") }.tag("markdown")
            HTMLSettingsView()
                .tabItem { Label("HTML", systemImage: "chevron.left.forwardslash.chevron.right") }.tag("html")
            editorSettings
                .tabItem { Label("Editor", systemImage: "textformat") }.tag("editor")
            Form { ShortcutPreferences(app: controller) }
                .formStyle(.grouped)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag("shortcuts")
        }
        .frame(width: 770, height: selectedTab == "bookmarks" ? 350 : 620)
        .onChange(of: appearance) { _, value in
            NSApp.appearance = ApplicationAppearance.resolved(value).nativeAppearance
        }
        .onChange(of: showInMenuBar) { _, value in
            AppDelegate.current?.setStatusItemVisible(value)
        }
    }

    private var editorSettings: some View {
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
        }.formStyle(.grouped)
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Text("Appearance:")
                    Picker("Appearance", selection: $appearance) {
                        ForEach(ApplicationAppearance.allCases, id: \.rawValue) { value in
                            Text(value.rawValue).tag(value.rawValue)
                        }
                    }.labelsHidden().frame(width: 100)
                    Button("Editor Settings…") { selectedTab = "editor" }
                    Spacer()
                }
                Divider()
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 205)
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 16) {
                    GridRow {
                        Text("Quick capture shortcut:").gridColumnAlignment(.trailing)
                        Text(controller.captureShortcutStatus)
                            .frame(width: 148, height: 24)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    GridRow {
                        Text("New draft after:")
                        Picker("New draft after", selection: $newDraftAfter) {
                            Text("Never").tag(0.0)
                            Text("30 seconds").tag(30.0)
                            Text("1 minute").tag(60.0)
                            Text("5 minutes").tag(300.0)
                            Text("15 minutes").tag(900.0)
                            Text("30 minutes").tag(1800.0)
                            Text("1 hour").tag(3600.0)
                        }
                        .labelsHidden().frame(width: 150)
                    }
                }
                Toggle("Use advanced find panel in editor", isOn: $preferAdvancedFind)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 205)
                Divider()
            }
            .padding(20)
        }
    }

    private var dataSettings: some View {
        Form {
            Section("Data") {
                if let library = controller.library { LibrarySyncStatusView(library: library) }
                else { Text("Library unavailable").font(.caption) }
                Button("Show Library Folder") {
                    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draftly")
                    NSWorkspace.shared.open(folder)
                }
                Text("Use File → Export Full Backup to save drafts, revisions, workspaces, and actions.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
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
