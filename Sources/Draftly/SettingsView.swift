import SwiftUI
import AppKit
import DraftlyCore

private struct NativeSettingsTabs: NSViewControllerRepresentable {
    struct Page {
        let id: String
        let title: String
        let symbol: String
        let content: AnyView

        init<Content: View>(_ id: String, _ title: String, _ symbol: String, _ content: Content) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.content = AnyView(content)
        }
    }

    @Binding var selection: String
    let pages: [Page]

    func makeNSViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.tabStyle = .toolbar
        controller.transitionOptions = []
        return controller
    }

    func updateNSViewController(_ controller: Controller, context: Context) {
        controller.isUpdating = true
        defer { controller.isUpdating = false }
        controller.onSelect = { selection = $0 }
        let ids = controller.tabViewItems.compactMap { $0.identifier as? String }
        if ids != pages.map(\.id) {
            for item in controller.tabViewItems {
                controller.removeTabViewItem(item)
            }
            for page in pages {
                let host = NSHostingController(rootView: page.content)
                host.sizingOptions = []
                host.preferredContentSize = NSSize(width: 770, height: page.id == "bookmarks" ? 350 : 620)
                host.title = page.title
                let item = NSTabViewItem(viewController: host)
                item.identifier = page.id
                item.label = page.title
                item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
                controller.addTabViewItem(item)
            }
        } else {
            for (item, page) in zip(controller.tabViewItems, pages) {
                (item.viewController as? NSHostingController<AnyView>)?.rootView = page.content
            }
        }
        if let index = pages.firstIndex(where: { $0.id == selection }),
           controller.selectedTabViewItemIndex != index {
            controller.selectedTabViewItemIndex = index
        }
        controller.configureWindow()
    }

    final class Controller: NSTabViewController {
        var isUpdating = false
        var onSelect: ((String) -> Void)?

        override func viewDidAppear() {
            super.viewDidAppear()
            configureWindow()
        }

        func configureWindow() {
            guard let window = view.window else { return }
            window.toolbarStyle = .preference
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .line
            window.toolbar?.displayMode = .iconAndLabel
            window.toolbar?.allowsUserCustomization = false
            window.title = tabView.selectedTabViewItem?.label ?? "Settings"
        }

        override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
            super.tabView(tabView, didSelect: tabViewItem)
            configureWindow()
            guard !isUpdating, let id = tabViewItem?.identifier as? String else { return }
            onSelect?(id)
        }
    }
}

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
        NativeSettingsTabs(selection: $selectedTab, pages: pages)
        .frame(width: 770, height: selectedTab == "bookmarks" ? 350 : 620)
        .navigationTitle(pages.first(where: { $0.id == selectedTab })?.title ?? "Settings")
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .onChange(of: appearance) { _, value in
            NSApp.appearance = ApplicationAppearance.resolved(value).nativeAppearance
        }
        .onChange(of: showInMenuBar) { _, value in
            AppDelegate.current?.setStatusItemVisible(value)
        }
    }

    private var pages: [NativeSettingsTabs.Page] {
        var pages: [NativeSettingsTabs.Page] = [
            .init("general", "General", "gearshape", generalSettings),
            .init("icloud", "iCloud", "icloud", dataSettings),
            .init("bookmarks", "Bookmarks", "bookmark", BookmarkSettingsView()),
            .init("markdown", "Markdown", "star.circle.fill", MarkdownSettingsView()),
            .init("html", "HTML", "chevron.left.forwardslash.chevron.right", HTMLSettingsView()),
            .init("editor", "Editor", "textformat", editorSettings),
            .init("maintenance", "Maintenance", "wrench.and.screwdriver", maintenanceSettings)
        ]
        if let agents = controller.agentSettings {
            pages.append(.init("agents", "Agents", "key", AgentConnectionsSettingsView(model: agents)))
        }
        pages.append(.init("shortcuts", "Shortcuts", "keyboard",
                           Form { ShortcutPreferences(app: controller) }.formStyle(.grouped)))
        return pages
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
