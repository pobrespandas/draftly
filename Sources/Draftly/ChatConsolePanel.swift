import SwiftUI
import AgentContracts

struct ChatConsolePanel: View {
    @ObservedObject var model: ChatConsoleModel
    var connectTools: (@MainActor () throws -> AgentChatToolSession)? = nil
    var toolsUnavailableReason = "Local agent access is unavailable in this build."
    var openAgentSettings: (() -> Void)? = nil
    var hasDraft = false
    @FocusState private var promptFocused: Bool
    @State private var showChatGPTAccount = false

    var body: some View {
        VStack(spacing: 0) {
            header
            toolsStatus
            Divider()
            if let conversation = model.selectedConversation, conversation.messages.isEmpty {
                emptyState
            } else {
                transcript
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            Divider()
            composer
        }
        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { await model.loadModels() }
        .sheet(isPresented: $showChatGPTAccount) {
            if let account = model.chatGPTAccount { ChatGPTAccountView(model: account) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.conversations) { conversation in
                    Button(conversation.title) { model.selectConversation(conversation.id) }
                }
                Divider()
                Button("New Chat", systemImage: "plus") { model.startConversation() }
            } label: {
                Image(systemName: "chevron.down.circle").font(.title3).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .help("Choose a conversation")

            Picker("Model", selection: $model.selectedModel) {
                if !model.availableModels.contains(model.selectedModel) {
                    Text(modelName(model.selectedModel)).tag(model.selectedModel).disabled(true)
                }
                ForEach(model.availableModels, id: \.self) { value in
                    Text(modelName(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
            .disabled(model.availableModels.isEmpty)

            Button { showChatGPTAccount = true } label: { Image(systemName: "person.crop.circle") }
                .help("ChatGPT Account")
            Button { model.startConversation() } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help("New Chat")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
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
                    Button("Disconnect") { model.disconnectTools() }
                } else if let openAgentSettings {
                    Button("Agent Settings…", action: openAgentSettings)
                } else if connectTools != nil && hasDraft && model.canConnectTools {
                    Button("Connect…", action: connectDraftTools)
                } else if connectTools != nil && hasDraft && model.selectedModel.hasPrefix("chatgpt:"),
                          model.chatGPTAccount?.isSignedIn == false {
                    Button("Sign In…") { showChatGPTAccount = true }
                }
            }
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
        if model.hasTools { return "Access is limited to this draft and editor." }
        if connectTools == nil { return toolsUnavailableReason }
        if !hasDraft { return "Open or save a draft to connect its tools." }
        if model.isResponding { return "Wait for the response to finish before connecting." }
        if model.selectedModel.hasPrefix("chatgpt:"), model.chatGPTAccount?.isSignedIn == false {
            return "Sign in to ChatGPT, then grant access to this draft."
        }
        if !model.canConnectTools { return "Choose an available model to connect draft tools." }
        return "Allow this chat to read or edit the open draft."
    }

    private func connectDraftTools() {
        guard let connectTools else { return }
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
                            messageView(message)
                                .id(message.id)
                        }
                    }
                    if model.isResponding {
                        if !model.streamingText.isEmpty {
                            Text(model.streamingText).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ProgressView().controlSize(.small).padding(.leading, 8).id("response")
                    }
                }
                .padding(14)
            }
            .onChange(of: model.selectedConversation?.messages.count) { _, _ in
                if let last = model.selectedConversation?.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: model.isResponding) { _, active in
                if active { proxy.scrollTo("response", anchor: .bottom) }
            }
            .onChange(of: model.streamingText) { _, _ in proxy.scrollTo("response", anchor: .bottom) }
        }
    }

    private func messageView(_ message: ChatConsoleMessage) -> some View {
        HStack {
            if message.role == .assistant { avatar }
            Text(message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            if message.role == .user { Spacer(minLength: 24) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var avatar: some View {
        Image(systemName: "sparkle").font(.caption).foregroundStyle(.secondary)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Enter a prompt", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($promptFocused)
                .onSubmit { model.send() }
                .padding(.vertical, 8)
            if model.isResponding {
                Button { model.cancelResponse() } label: {
                    Image(systemName: "stop.fill").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .help("Stop response")
            } else {
                Button { model.send() } label: {
                    Image(systemName: "arrow.up").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSend)
                .help("Send prompt")
            }
        }
        .padding(12)
    }

    private func modelName(_ value: String) -> String {
        model.modelName(value)
    }
}


struct LocalChatConsolePanel: View {
    @ObservedObject var model: ChatConsoleModel
    @ObservedObject var settings: AgentConnectionsSettingsModel
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
            }, hasDraft: hasDraft)
    }
}
