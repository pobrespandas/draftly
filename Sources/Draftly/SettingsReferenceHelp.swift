import SwiftUI
import AppKit
import DraftlyCore

struct SettingsReferenceHelp: View {
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
