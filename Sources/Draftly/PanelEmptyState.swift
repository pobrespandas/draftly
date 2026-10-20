import SwiftUI
import AppKit
import DraftlyCore

struct PanelEmptyState: View {
    var message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "curlybraces").font(.system(size: 32, weight: .light))
            Text(message).font(.system(size: 13))
        }
        .foregroundStyle(.secondary).padding(.top, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
