import SwiftUI
import AppKit
import DraftlyCore

struct DraftFiltersPanel: View {
    @ObservedObject var model: WindowModel
    @Binding var showTagSearch: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: model.activeTagFilters.isEmpty && model.excludedTagFilters.isEmpty && model.tagPresence == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill").font(.system(size: 20))
                Text("Filters").font(.system(size: 12, weight: .bold)).textCase(.uppercase).tracking(0.35).lineLimit(1).minimumScaleFactor(0.75)
                Spacer()
                Button { model.clearFilters() } label: { Image(systemName: "xmark.circle").font(.system(size: 20, weight: .light)) }.help("Clear Filters")
                PanelMenu(symbol: "ellipsis.circle", help: "Filter Options", items: [
                    PanelMenuItem(title: showTagSearch ? "Hide Search" : "Show Search") {
                        showTagSearch.toggle()
                        if !showTagSearch { model.tagQuery = "" }
                    },
                    .section("Selection Mode"),
                    PanelMenuItem(title: "Single Tag", isOn: !model.multipleTagMode) { model.setMultipleTagMode(false) },
                    PanelMenuItem(title: "Multiple Tags", isOn: model.multipleTagMode) { model.setMultipleTagMode(true) },
                    .section("Show"),
                    PanelMenuItem(title: "All Tags", isOn: !model.showOnlyCurrentTags) { model.showOnlyCurrentTags = false },
                    PanelMenuItem(title: "Only Current Tags", isOn: model.showOnlyCurrentTags) { model.showOnlyCurrentTags = true }

                ]).frame(width: 20, height: 20)
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, MainWindowStyle.sidebarInset).frame(height: 40).offset(y: 6)

            if !model.activeTagFilters.isEmpty || !model.excludedTagFilters.isEmpty || model.tagPresence != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(model.activeTagFilters, id: \.self) { tag in
                            filterChip(tag, color: .accentColor) { model.removeTagFilter(tag) }
                        }
                        ForEach(model.excludedTagFilters, id: \.self) { tag in
                            filterChip("−\(tag)", color: .red) { model.removeTagFilter(tag, excluded: true) }
                        }
                        if let tagged = model.tagPresence { filterChip(tagged ? "tagged" : "untagged", color: .secondary) { model.tagPresence = nil } }
                    }.padding(.horizontal, 16).padding(.top, 10)
                }.frame(height: 60, alignment: .top)
            } else {
                Text("No tag filters active").font(.system(size: 11)).italic().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MainWindowStyle.sidebarInset).padding(.top, 17)
                    .frame(height: 60, alignment: .top)
            }
            if showTagSearch {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Filter tags", text: $model.tagQuery).textFieldStyle(.plain).font(.system(size: 12))
                    if !model.tagQuery.isEmpty { Button { model.tagQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary) }
                }.padding(.horizontal, 8).frame(height: 25).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 5)).padding(.horizontal, 12).padding(.bottom, 4)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.circle").font(.system(size: 20, weight: .light))
                        Text("Tags")
                    }.font(.system(size: 12, weight: .bold)).textCase(.uppercase).tracking(0.3)
                        .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 7).padding(.bottom, 7).offset(y: MainWindowStyle.tagsHeadingOffset)
                    Button { model.tagPresence = model.tagPresence == true ? nil : true } label: { filterRow("tagged", symbol: "tag.fill", selected: model.tagPresence == true) }
                        .buttonStyle(.plain).padding(.horizontal, 9).frame(height: 32).background(model.tagPresence == true ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityLabel("Tagged, \(model.taggedCount) drafts")
                    Button { model.tagPresence = model.tagPresence == false ? nil : false } label: { filterRow("untagged", symbol: "tag.fill", selected: model.tagPresence == false) }
                        .buttonStyle(.plain).padding(.horizontal, 9).frame(height: 32).background(model.tagPresence == false ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityLabel("Untagged, \(model.untaggedCount) drafts")
                    ForEach(model.matchingTags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Button { model.toggleTag(tag) } label: { filterRow(tag, symbol: "tag", selected: model.selectedTags.contains(tag)) }
                                .buttonStyle(.plain).accessibilityLabel("Filter by tag \(tag), \(model.count(forTag: tag)) drafts")
                            if model.multipleTagMode {
                                Button { model.toggleExcludedTag(tag) } label: {
                                    TagGlyph(symbol: model.excludedTags.contains(tag) ? "minus.circle.fill" : "minus.circle")
                                        .foregroundStyle(model.excludedTags.contains(tag) ? Color.red : Color.secondary.opacity(0.45))
                                }.buttonStyle(.plain).help("Exclude tag \(tag)")
                            }
                        }
                        .padding(.horizontal, 9).frame(height: 32)
                        .background(model.selectedTags.contains(tag) || model.excludedTags.contains(tag) ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contextMenu {
                            Button("Rename Tag") { model.promptRenameTag(tag) }
                            Button("Delete Tag") { model.promptDeleteTag(tag) }
                        }
                    }
                    if model.matchingTags.isEmpty { Text(model.allTags.isEmpty ? "No tags yet" : "No matching tags").font(.system(size: 12)).foregroundStyle(.secondary).padding(12) }
                }.padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func filterRow(_ title: String, symbol: String, selected: Bool = false) -> some View {
        HStack(spacing: 12) {
            TagGlyph(symbol: symbol, weight: .medium).foregroundStyle(selected ? Color.white : Color.accentColor)
            Text(title).fontWeight(selected ? .semibold : .regular).lineLimit(1)
            Spacer(minLength: 6)
        }.font(.system(size: 13)).foregroundStyle(selected ? Color.white : Color.primary.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
    }
    private func filterChip(_ title: String, color: Color, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary.opacity(0.6)) }
                .buttonStyle(.plain).accessibilityLabel("Remove \(title)")
        }
        .font(.system(size: 12)).foregroundStyle(.primary)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.2)))
    }

}

private struct TagGlyph: View {
    let symbol: String
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .font(.system(size: 11, weight: weight))
            .frame(width: 11, height: 11)
            .frame(width: 14, height: 14)
    }
}
