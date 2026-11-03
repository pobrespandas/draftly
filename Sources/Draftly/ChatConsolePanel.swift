import SwiftUI

struct ChatConsolePanel: View {
    @ObservedObject var model: ChatConsoleModel
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
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

            Menu {
                if model.availableModels.isEmpty {
                    Text("Apple Intelligence is unavailable")
                } else {
                    ForEach(model.availableModels, id: \.self) { value in
                        Button {
                            model.selectedModel = value
                        } label: {
                            if model.selectedModel == value { Label(modelName(value), systemImage: "checkmark") }
                            else { Text(modelName(value)) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(modelName(model.selectedModel)).font(.headline)
                    Image(systemName: "chevron.down").font(.caption2)
                }.foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)
            .disabled(model.availableModels.isEmpty)

            Spacer()
            Button { model.startConversation() } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help("New Chat")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Chat Console").font(.title3.weight(.semibold))
            Text("Ask about your drafts or get help writing.")
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
                .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.availableModels.isEmpty)
                .help("Send prompt")
            }
        }
        .padding(12)
    }

    private func modelName(_ value: String) -> String {
        switch value {
        case "onDevice": "On-Device"
        case "pcc": "Cloud"
        default: "Choose Model"
        }
    }
}
