import SwiftUI
import AppKit
import DraftlyCore

struct BookmarkSettingsView: View {
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
