import SwiftUI
import AgentContracts
import DraftlyCore

/// Compose a panel without coupling its content to a window model.
struct WritingPanel<Header: View, Content: View, Status: View, Footer: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @ViewBuilder var status: () -> Status
    @ViewBuilder var footer: () -> Footer
    var body: some View {
        VStack(spacing: 0) {
            header()
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
            status()
            footer()
        }
    }
}

struct ChatConsolePanel: View {
    @ObservedObject var model: ChatConsoleModel
    var connectTools: (@MainActor () throws -> AgentChatToolSession)? = nil
    var toolsUnavailableReason = "Local agent access is unavailable in this build."
    var openAgentSettings: (() -> Void)? = nil
    var editorTheme: EditorTheme? = nil
    var contentFont: Font = .body
    var createDraft: ((String) -> Void)? = nil
    var insertText: ((String) -> Void)? = nil
    var hasDraft = false
    @StateObject private var promptSession = EditorSession()
    @State private var promptHeight: CGFloat = 38
    @AppStorage("editor.fontName") private var promptFontName = EditorPreferenceDefaults.fontName
    @AppStorage("editor.fontSize") private var promptFontSize = EditorPreferenceDefaults.fontSize
    @AppStorage(EditorSyntaxFontPreferences.key) private var promptSyntaxFonts = "{}"
    @State private var showChatGPTAccount = false
    @State private var followsResponse = true
    @State private var userIsScrolling = false

    var body: some View {
        WritingPanel(header: {
            header
            toolsStatus
            Divider()
        }, content: {
            if let conversation = model.selectedConversation, conversation.messages.isEmpty {
                emptyState
            } else {
                transcript
            }
        }, status: {
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }, footer: {
            Divider()
            composer
        })
        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { await model.loadModels() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { model.refreshToolExpiry(now: $0) }
        .sheet(isPresented: $showChatGPTAccount) {
            if let account = model.chatGPTAccount { ChatGPTAccountView(model: account) }
        }
    }

    private var header: some View {
        HStack(spacing: MainWindowStyle.utilityTrailingSpacing) {
            PanelMenu(symbol: "chevron.down.circle", help: "Choose a conversation", items:
                model.conversations.map { conversation in
                    PanelMenuItem(title: conversation.title, isOn: conversation.id == model.selectedConversation?.id) {
                        model.selectConversation(conversation.id)
                    }
                } + [.separator, PanelMenuItem(title: "New Chat") { model.startConversation() }]
            ).frame(width: 28, height: 28)

            Menu {
                Picker("Model", selection: $model.selectedModel) {
                    if !model.availableModels.contains(model.selectedModel) {
                        Text(model.modelName(model.selectedModel)).tag(model.selectedModel).disabled(true)
                    }
                    ForEach(model.availableModels, id: \.self) { value in
                        Text(model.modelName(value)).tag(value)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(modelLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Model")
            .accessibilityValue(model.modelName(model.selectedModel))
            .help(model.modelName(model.selectedModel))
            .disabled(model.availableModels.isEmpty)

            Button { showChatGPTAccount = true } label: { PanelIcon(symbol: "person.crop.circle") }
                .help("ChatGPT Account")
            Button { model.startConversation() } label: { PanelIcon(symbol: "plus") }
                .help("New Chat")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, MainWindowStyle.utilityInset)
        .frame(height: MainWindowStyle.utilityHeight)
    }

    private var modelLabel: String {
        switch model.selectedModel {
        case "onDevice": "On-Device"
        case "pcc": "Apple Cloud"
        default: model.modelName(model.selectedModel)
        }
    }

    private var toolsStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(model.hasTools ? "Draft tools connected" : "Draft tools off",
                      systemImage: model.hasTools ? "checkmark.shield" : "wrench.and.screwdriver")
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 4)
                if model.hasTools {
                    Button("Disconnect") { model.automaticToolsEnabled = false; model.disconnectTools() }
                } else if let openAgentSettings {
                    Button("Agent Settings…", action: openAgentSettings)
                } else if connectTools != nil && model.canConnectTools {
                    Button("Connect…", action: connectDraftTools)
                } else if connectTools != nil && model.selectedModel.hasPrefix("chatgpt:"),
                          model.chatGPTAccount?.isSignedIn == false {
                    Button("Sign In…") { showChatGPTAccount = true }
                }
            }
            .buttonStyle(.link)
            .controlSize(.small)
            Text(toolsStatusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolsStatusDetail: String {
        if model.hasTools { return "Connected to the library. Tools check your current permissions on every call." }
        if connectTools == nil { return toolsUnavailableReason }
        if model.isResponding { return "Wait for the response to finish before connecting." }
        if model.selectedModel.hasPrefix("chatgpt:"), model.chatGPTAccount?.isSignedIn == false {
            return "Sign in to ChatGPT, then connect Draftly tools."
        }
        if !model.canConnectTools { return "Choose an available model to connect draft tools." }
        return "Connect tools to create, find and edit drafts in your library."
    }

    private func connectDraftTools() {
        guard let connectTools else { return }
        model.automaticToolsEnabled = true
        do { try model.connectTools(connectTools()) }
        catch is CancellationError {}
        catch let error as AgentErrorCode where error == .cancelled {}
        catch { model.reportToolError(error) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Chat Console").font(.title3.weight(.semibold))
            Text("Get help writing and developing ideas.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 250)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let conversation = model.selectedConversation {
                        ForEach(conversation.messages) { message in
                            messageView(message.text, role: message.role)
                                .id(message.id)
                        }
                    }
                    if model.isResponding {
                        if !model.streamingText.isEmpty {
                            messageView(model.streamingText, role: .assistant)
                        }
                        ProgressView().controlSize(.small).padding(.leading, 8).id("response")
                    }
                }
                .padding(14)
                Color.clear.frame(height: 1).id("chat-bottom")
            }
            .onScrollPhaseChange { _, phase in
                userIsScrolling = phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 60
            } action: { _, nearBottom in
                if userIsScrolling { followsResponse = nearBottom }
            }
            .onChange(of: model.selectedConversation?.messages.count) { _, _ in
                if model.selectedConversation?.messages.last?.role == .user { followsResponse = true }
                if followsResponse { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            .onChange(of: model.isResponding) { _, active in
                if active && followsResponse { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            .onChange(of: model.streamingText) { _, _ in if followsResponse { proxy.scrollTo("chat-bottom", anchor: .bottom) } }
            .onChange(of: model.selectedConversationID) { _, _ in
                followsResponse = true
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                if !followsResponse {
                    Button {
                        followsResponse = true
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    } label: { Label("Latest message", systemImage: "arrow.down") }
                    .buttonStyle(.bordered).padding(12)
                }
            }
        }
    }

    private func messageView(_ text: String, role: ChatConsoleMessage.Role) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if role == .user {
                Spacer(minLength: 24)
            } else {
                Image(systemName: "sparkle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                if role == .assistant { ChatMarkdown(text: text) }
                else { Text(text).textSelection(.enabled) }
                if role == .assistant, !model.isResponding {
                    HStack {
                        if let createDraft { Button("Create draft") { createDraft(text) } }
                        if let insertText { Button("Insert") { insertText(text) } }
                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                    }.buttonStyle(.link).controlSize(.small)
                }
            }
                .font(contentFont)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10))
            if role == .assistant { Spacer(minLength: 16) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(role == .user ? "You" : "Assistant")
    }

    private var composer: some View {
        let promptFont = EditorSyntaxFontPreferences.font(for: "Markdown", encoded: promptSyntaxFonts,
            defaultName: promptFontName, defaultSize: promptFontSize)
        let nativeFont = NSFont(name: promptFont.name, size: promptFont.size) ?? NSFont.systemFont(ofSize: promptFont.size)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: nativeFont)
        return HStack(alignment: .bottom, spacing: 8) {
            NativeEditor(session: promptSession, fontName: promptFont.name,
                fontSize: promptFont.size, lineSpacing: 0, markdown: true,
                horizontalMargin: 0, verticalMargin: 8, maximumWidth: 0, theme: editorTheme,
                submit: { model.send() }, measuredHeight: { if abs(promptHeight - $0) > 0.5 { promptHeight = $0 } }, independentUndo: true) { model.prompt = promptSession.content }
                .frame(height: min(max(promptHeight, lineHeight + 16), lineHeight * 5 + 16))
                .accessibilityLabel("Enter a prompt")
                .id(model.selectedConversation?.id)
                .onChange(of: model.prompt) { _, value in
                    if promptSession.content != value {
                        promptSession.content = value
                        promptSession.selection = NSRange(location: value.utf16.count, length: 0)
                    }
                }
                .onChange(of: model.selectedConversation?.id) { _, _ in
                    promptSession.content = model.prompt
                }
            Button {
                if model.isResponding { model.cancelResponse() } else { model.send() }
            } label: {
                Image(systemName: model.isResponding ? "stop.fill" : "arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(!model.isResponding && !model.canSend)
            .accessibilityLabel(model.isResponding ? "Stop response" : "Send prompt")
            .help(model.isResponding ? "Stop response" : "Send prompt")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct LocalChatConsolePanel: View {
    @ObservedObject var model: ChatConsoleModel
    @ObservedObject var settings: AgentConnectionsSettingsModel
    var editorTheme: EditorTheme? = nil
    var contentFont: Font = .body
    var createDraft: ((String) -> Void)? = nil
    var insertText: ((String) -> Void)? = nil
    let hasDraft: Bool
    let connectTools: @MainActor () throws -> AgentChatToolSession
    @Environment(\.openSettings) private var openSettings
    @AppStorage("settings.selectedTab") private var selectedTab = "general"

    var body: some View {
        ChatConsolePanel(model: model, connectTools: settings.accessEnabled ? connectTools : nil,
            toolsUnavailableReason: "Enable local agent access to let this chat read or edit a draft.",
            openAgentSettings: settings.accessEnabled ? nil : {
                selectedTab = "agents"
                openSettings()
            }, editorTheme: editorTheme, contentFont: contentFont, createDraft: createDraft, insertText: insertText, hasDraft: hasDraft)
            .task(id: model.selectedModel + String(settings.accessEnabled) + String(model.canConnectTools) + (model.selectedConversation?.id.uuidString ?? "")) {
                await model.loadModels()
                guard settings.accessEnabled, model.automaticToolsEnabled,
                      model.canConnectTools, !model.hasTools else { return }
                do { try model.connectTools(connectTools()) }
                catch { model.reportToolError(error) }
            }
    }
}
