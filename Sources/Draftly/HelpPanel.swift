import SwiftUI
import DraftlyCore

struct HelpPanel: View {
    @State private var articles: [HelpArticle] = []
    @State private var selectedID: String? = "01-start"
    @State private var query = ""
    @State private var error: String?

    private var results: [HelpArticle] { articles.filter { $0.matches(query) } }
    private var categories: [String] {
        results.reduce(into: []) { if !$0.contains($1.category) { $0.append($1.category) } }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(categories, id: \.self) { category in
                    Section(category) {
                        ForEach(results.filter { $0.category == category }) { article in
                            Text(article.title).tag(article.id)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search Draftly Help")
            .navigationTitle("Draftly Help")
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 330)
            .overlay {
                if results.isEmpty && error == nil {
                    ContentUnavailableView.search(text: query)
                }
            }
        } detail: {
            if let error {
                ContentUnavailableView {
                    Label("Help could not load", systemImage: "book.closed")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again", action: load)
                }
            } else if let article = articles.first(where: { $0.id == selectedID }) {
                ScrollView {
                    ChatMarkdown(text: article.markdown)
                        .font(.body)
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(article.id)
                .navigationTitle(article.title)
                .accessibilityLabel(article.title)
            } else {
                ContentUnavailableView("Choose a help topic", systemImage: "book")
            }
        }
        .frame(minWidth: 680, minHeight: 420)
        .task { load() }
    }

    private func load() {
        do { articles = try HelpGuide.articles(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
