import SwiftUI
import AppKit
import DraftlyCore

enum GeneralPreferences {
    static let showInMenuBarKey = "application.showInMenuBar"
    static let advancedFindKey = "editor.preferAdvancedFind"

    static func showInMenuBar(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showInMenuBarKey) as? Bool ?? true
    }
}

enum ApplicationAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    static let preferenceKey = "application.appearance"

    static func resolved(_ value: String) -> ApplicationAppearance {
        ApplicationAppearance(rawValue: value) ?? .system
    }

    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
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
            Form { ShortcutPreferences() }
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
                        Text(AppController.shared.captureShortcutStatus)
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
                if let library = AppController.shared.library { LibrarySyncStatusView(library: library) }
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


enum BookmarkPreferences {
    static func data(for url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: .withSecurityScope)
    }

    static func names(defaults: UserDefaults = .standard) -> [String] {
        defaults.dictionaryRepresentation().compactMap { key, value in
            guard key.hasPrefix("bookmark."), value is Data else { return nil }
            let name = String(key.dropFirst("bookmark.".count))
            return name.isEmpty ? nil : name
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func forget(_ name: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "bookmark." + name)
    }
}

private struct BookmarkSettingsView: View {
    @State private var names: [String] = []
    @State private var adding = false
    @State private var name = ""
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    private var validName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !names.contains(name)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            List {
                ForEach(names, id: \.self) { value in
                    HStack {
                        Text(value)
                        Spacer()
                        Button("Forget") {
                            BookmarkPreferences.forget(value)
                            names = BookmarkPreferences.names()
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .border(Color(nsColor: .separatorColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 14) {
                Button("Add Bookmark") { name = ""; error = nil; adding = true }
                Text("Folder bookmarks let actions read and write files in a folder you select. Actions can also create bookmarks when needed.")
                Text("Forget a bookmark to remove its saved permission. If an action needs it again, Draftly will ask you to select the folder again.")
            }
            .frame(width: 318, alignment: .leading)
        }
        .padding(20)
        .overlay(alignment: .bottomTrailing) { SettingsReferenceHelp(topic: "bookmarks", title: "Bookmarks").padding(16) }
        .onAppear { names = BookmarkPreferences.names() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            names = BookmarkPreferences.names()
        }
        .sheet(isPresented: $adding) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Bookmark").font(.headline)
                Text("Enter a unique name, then select the folder to associate with the bookmark.")
                TextField("Bookmark Name", text: $name).focused($nameFocused)
                if names.contains(name) { Text("A bookmark with this name already exists.").foregroundStyle(.red) }
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button("Cancel") { adding = false }.keyboardShortcut(.cancelAction)
                    Button("Select Folder") { selectFolder() }
                        .keyboardShortcut(.defaultAction).disabled(!validName)
                }
            }
            .padding(20).frame(width: 430)
            .onAppear { nameFocused = true }
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder for \(name)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try BookmarkPreferences.data(for: url)
            guard !BookmarkPreferences.names().contains(name) else {
                error = "A bookmark with this name already exists."
                names = BookmarkPreferences.names()
                return
            }
            UserDefaults.standard.set(data, forKey: "bookmark." + name)
            names = BookmarkPreferences.names()
            adding = false
        } catch {
            NSLog("Bookmark creation failed: %@", String(reflecting: error))
            self.error = error.localizedDescription
        }
    }
}


private struct SettingsReferenceHelp: View {
    let topic: String
    let title: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: "https://docs.getdrafts.com/docs/settings/" + topic) { openURL(url) }
        } label: { Image(systemName: "questionmark.circle").font(.system(size: 18)).foregroundStyle(.secondary) }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " reference help")
        .help("Open the Drafts " + title + " reference")
    }
}

private struct MarkdownSettingsView: View {
    @AppStorage(MarkdownPreferences.engineKey) private var processor = "multi"
    @AppStorage(MarkdownPreferences.multiKey) private var multiOptions = "{}"
    @AppStorage(MarkdownPreferences.githubKey) private var githubOptions = "{}"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose the default Markdown processor for previews and Markdown conversion actions.")
                Picker("Markdown processor", selection: $processor) {
                    Text("MultiMarkdown").tag("multi")
                    Text("GitHub Markdown").tag("github")
                }.pickerStyle(.radioGroup).labelsHidden()
                HStack(alignment: .top, spacing: 24) {
                    optionsGroup("MultiMarkdown Options", engine: "multi", options: MarkdownPreferences.multiOptions, json: $multiOptions)
                    optionsGroup("GitHub Markdown Options", engine: "github", options: MarkdownPreferences.githubOptions, json: $githubOptions)
                }
            }.padding(20)
        }
        .overlay(alignment: .bottomTrailing) { SettingsReferenceHelp(topic: "markdown", title: "Markdown").padding(16) }
    }

    private func optionsGroup(_ title: String, engine: String, options: [MarkdownPreferences.Option], json: Binding<String>) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(options) { option in
                    Toggle(option.title, isOn: Binding(get: {
                        MarkdownPreferences.options(engine: engine, json: json.wrappedValue)[option.id] ?? option.defaultValue
                    }, set: { value in
                        var values = MarkdownPreferences.options(engine: engine, json: json.wrappedValue)
                        values[option.id] = value
                        if let data = try? JSONEncoder().encode(values) { json.wrappedValue = String(decoding: data, as: UTF8.self) }
                    })).toggleStyle(.checkbox)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }.disabled(processor != engine)
    }
}


enum HTMLPreferences {
    static let pasteKey = "html.pasteAsMarkdown"
    static func options(defaults: UserDefaults = .standard) -> [String: Any] {
        let strong = defaults.string(forKey: "html.strongMark") ?? "**"
        let emphasis = defaults.string(forKey: "html.emphasisMark") ?? "_"
        let list = defaults.string(forKey: "html.ulItemMark") ?? "-"
        return [
            "strongMark": ["**", "__"].contains(strong) ? strong : "**",
            "emphasisMark": ["*", "_"].contains(emphasis) ? emphasis : "_",
            "ulItemMark": ["*", "-"].contains(list) ? list : "-",
            "inlineLinks": defaults.object(forKey: "html.inlineLinks") as? Bool ?? true,
            "linksEachParagraph": defaults.bool(forKey: "html.linksEachParagraph"),
            "ignoreLinks": defaults.bool(forKey: "html.ignoreLinks"),
            "ignoreImages": defaults.bool(forKey: "html.ignoreImages"),
            "ignoreEmphasis": defaults.bool(forKey: "html.ignoreEmphasis")
        ]
    }
}

private struct HTMLSettingsView: View {
    @AppStorage(HTMLPreferences.pasteKey) private var paste = true
    @AppStorage("html.strongMark") private var strong = "**"
    @AppStorage("html.emphasisMark") private var emphasis = "_"
    @AppStorage("html.ulItemMark") private var list = "-"
    @AppStorage("html.inlineLinks") private var inlineLinks = true
    @AppStorage("html.linksEachParagraph") private var linksEachParagraph = false
    @AppStorage("html.ignoreLinks") private var ignoreLinks = false
    @AppStorage("html.ignoreImages") private var ignoreImages = false
    @AppStorage("html.ignoreEmphasis") private var ignoreEmphasis = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose how HTML converts to Markdown when you paste in the editor.")
                Toggle("Paste HTML as Markdown", isOn: $paste)
                GroupBox("HTML → Markdown") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Strong Mark", selection: $strong) { Text("**").tag("**"); Text("__").tag("__") }
                        Picker("Emphasis Mark", selection: $emphasis) { Text("_").tag("_"); Text("*").tag("*") }
                        Picker("List Mark", selection: $list) { Text("-").tag("-"); Text("*").tag("*") }
                        Toggle("Inline links", isOn: $inlineLinks)
                        Toggle("Links after each paragraph", isOn: $linksEachParagraph)
                            .disabled(inlineLinks || ignoreLinks)
                        Toggle("Ignore links", isOn: $ignoreLinks)
                        Toggle("Ignore images", isOn: $ignoreImages)
                        Toggle("Ignore emphasis", isOn: $ignoreEmphasis)
                    }.padding(12)
                }
            }.toggleStyle(.checkbox).padding(20)
        }
        .overlay(alignment: .bottomTrailing) { SettingsReferenceHelp(topic: "htmltomarkdown", title: "HTML to Markdown").padding(16) }
    }
}
