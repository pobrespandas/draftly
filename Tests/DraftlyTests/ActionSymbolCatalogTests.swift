import Foundation
import SwiftUI
import Testing
@testable import Draftly

@Suite("Action symbol catalog")
struct ActionSymbolCatalogTests {
    @Test func catalogKeepsTheExistingChoicesFirstAndUsesUniqueStableIdentities() {
        let existing = ["bolt", "doc.on.doc", "square.and.arrow.up", "folder", "checklist", "calendar",
                        "envelope", "message", "terminal", "globe", "wand.and.stars", "pencil"]
        let options = ActionSymbolCatalog.options
        #expect(Array(options.prefix(existing.count).map(\.name)) == existing)
        #expect(Set(options.map(\.id)).count == options.count)
        #expect(options.allSatisfy { !$0.name.isEmpty && !$0.title.isEmpty })
        #expect(ActionSymbolCatalog.options(matching: " \n ", currentSymbol: "bolt") == options)
    }

    @Test func searchMatchesNamesTitlesAndKeywordsWithoutChangingOrder() {
        #expect(ActionSymbolCatalog.options(matching: "DOC.ON.DOC", currentSymbol: "bolt").map(\.name) == ["doc.on.doc"])
        #expect(ActionSymbolCatalog.options(matching: "cÁmÉra", currentSymbol: "bolt").map(\.name) == ["camera"])
        #expect(ActionSymbolCatalog.options(matching: " dictation AUDIO ", currentSymbol: "bolt").map(\.name) == ["mic"])
        let audio = ActionSymbolCatalog.options(matching: "audio", currentSymbol: "bolt")
        #expect(audio.map(\.name) == ["mic", "speaker.wave.2", "waveform"])
        #expect(ActionSymbolCatalog.options(matching: "not-in-this-catalog", currentSymbol: "bolt").isEmpty)
    }

    @Test(arguments: ["future.symbol.café.🐼", "  imported symbol  ", ""])
    func currentSymbolIsPreservedWithoutNormalizationOrFallback(symbol: String) {
        let options = ActionSymbolCatalog.options(matching: "", currentSymbol: symbol)
        if symbol.isEmpty {
            #expect(options == ActionSymbolCatalog.options)
        } else {
            #expect(options.first?.name == symbol)
            #expect(options.first?.id == symbol)
            #expect(ActionSymbolCatalog.options(matching: "imported", currentSymbol: symbol).first?.name == symbol)
        }
        #expect(ActionSymbolCatalog.options(matching: "no-results", currentSymbol: symbol).isEmpty)
        #expect(ActionSymbolCatalog.options(matching: "", currentSymbol: symbol) == options)
    }

    @MainActor @Test func constructingAndReadingPickerDoesNotWriteItsBinding() {
        var imported = "future.symbol.café.🐼"
        var writes = 0
        let picker = ActionSymbolPicker(symbol: Binding(get: { imported }, set: { imported = $0; writes += 1 }))
        _ = picker.body
        #expect(imported == "future.symbol.café.🐼")
        #expect(writes == 0)
    }
}
