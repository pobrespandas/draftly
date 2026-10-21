import SwiftUI

struct ActionMessageBanner: Identifiable {
    enum Severity: String {
        case info, success, warning, error
        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .info: .blue
            case .success: .green
            case .warning: .orange
            case .error: .red
            }
        }
    }
    let id = UUID()
    let message: String
    let severity: Severity
}

struct ActionMessageBannerView: View {
    let banner: ActionMessageBanner
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: banner.severity.symbol).foregroundStyle(banner.severity.color)
                .accessibilityLabel(banner.severity.rawValue.capitalized)
            Text(banner.message).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss message")
        }
        .padding(12)
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(banner.severity.color.opacity(0.5)) }
        .accessibilityElement(children: .contain)
    }
}
