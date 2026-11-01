import SwiftUI
import AppKit
import DraftlyCore

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @StateObject private var loginItem = LoginItemPreferences()
    @AppStorage("settings.selectedTab") private var selectedTab = "general"
    @AppStorage(ApplicationAppearance.preferenceKey) private var appearance = "System"
    @AppStorage(GeneralPreferences.showInMenuBarKey) private var showInMenuBar = GeneralPreferences.defaultMenuBarVisibility
    @AppStorage(GeneralPreferences.showMainWindowAtLaunchKey) private var showMainWindowAtLaunch = GeneralPreferences.defaultMainWindowVisibility
    @AppStorage(GeneralPreferences.advancedFindKey) private var preferAdvancedFind = GeneralPreferences.defaultAdvancedFind
    @AppStorage(GeneralPreferences.showCustomTouchBarKey) private var showCustomTouchBar = GeneralPreferences.defaultTouchBar
    @AppStorage(ActionMoveNavigation.preferenceKey) private var actionMoveNavigation = ActionMoveNavigation.createNew.rawValue
    @AppStorage("capture.newDraftAfter") private var newDraftAfter = CaptureDefaults.newDraftAfter
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
            maintenanceSettings
                .tabItem { Label("Maintenance", systemImage: "wrench.and.screwdriver") }.tag("maintenance")
            if let agents = controller.agentSettings {
                AgentConnectionsSettingsView(model: agents)
                    .tabItem { Label("Agents", systemImage: "key") }.tag("agents")
            }
            Form { ShortcutPreferences(app: controller) }
                .formStyle(.grouped)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag("shortcuts")
        }
        .frame(width: 770, height: selectedTab == "bookmarks" ? 350 : 620)
        .transaction(value: selectedTab) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .onChange(of: appearance) { _, value in
            NSApp.appearance = ApplicationAppearance.resolved(value).nativeAppearance
        }
        .onChange(of: showInMenuBar) { _, value in
            AppDelegate.current?.setStatusItemVisible(value)
        }
    }

    @ViewBuilder private var editorSettings: some View {
        if let library = controller.library { EditorSettingsView(library: library) }
        else { Text("Library unavailable").foregroundStyle(.secondary) }
    }

    @ViewBuilder private var maintenanceSettings: some View {
        if let library = controller.library { MaintenanceSettingsView(library: library) }
        else { Text("Library unavailable").foregroundStyle(.secondary) }
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
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { loginItem.isRegistered },
                        set: { enabled in Task { await loginItem.setEnabled(enabled) } }
                    ))
                    .disabled(loginItem.isChanging || loginItem.status == .unavailable)
                    if loginItem.status == .requiresApproval {
                        Text("Allow Draftly in System Settings → Login Items.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Login Items") { LoginItemPreferences.openSettings() }
                    } else if loginItem.status == .unavailable {
                        Text("Login registration is unavailable for this app installation.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = loginItem.error {
                        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 205)
                .onAppear { loginItem.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    loginItem.refresh()
                }
                Toggle("Show main window at launch", isOn: $showMainWindowAtLaunch)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 205)
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 205)
                if let spotlight = controller.spotlight {
                    SpotlightSettingsView(preferences: spotlight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 205)
                }
                Toggle("Show custom TouchBar in editor (when available)", isOn: $showCustomTouchBar)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 205)
                Divider()
                GlobalShortcutPreferences(app: controller)
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 16) {
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
                HStack {
                    Text("When Action “After Success” Moves Draft:")
                    Picker("After Success navigation", selection: $actionMoveNavigation) {
                        ForEach(ActionMoveNavigation.allCases, id: \.rawValue) { value in
                            Text(value.rawValue).tag(value.rawValue)
                        }
                    }.labelsHidden().frame(width: 170)
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
                Text("Use File → Export Full Backup to save drafts, revisions, workspaces, actions, themes, and execution history.").font(.caption).foregroundStyle(.secondary)
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


private struct SpotlightSettingsView: View {
    @ObservedObject var preferences: SpotlightPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Index drafts in Spotlight", isOn: Binding(
                get: { preferences.isEnabled }, set: { preferences.setEnabled($0) }))
                .toggleStyle(.checkbox)
                .disabled(!preferences.isAvailable)
            if !preferences.isAvailable {
                Text("Spotlight indexing is unavailable on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if preferences.isChanging {
                Text("Updating Spotlight…").font(.caption).foregroundStyle(.secondary)
            }
            if let error = preferences.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                Button("Try Again") { preferences.retry() }
            }
        }
    }
}
