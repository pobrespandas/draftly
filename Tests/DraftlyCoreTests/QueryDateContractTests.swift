import Foundation
import Testing
@testable import DraftlyCore

@Suite("QueryDate evaluation contracts")
struct QueryDateContractTests {
    private func workspace(_ query: [String: Any], key: String) throws -> Workspace {
        var value = Workspace(name: "Date contract")
        value.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: [key: query]), as: UTF8.self)]
        return value
    }

    @Test func absoluteDateUsesWholeDayForEachField() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let start = calendar.startOfDay(for: noon)
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(end.timeIntervalSince(start) == 23 * 3600)
        for field in ["created", "modified", "accessed"] {
            let query: [String: Any] = ["type": "absolute", "field": field, "date": ISO8601DateFormatter().string(from: noon)]
            let lower = try workspace(query, key: "startDate")
            let upper = try workspace(query, key: "endDate")
            for (date, lowerMatches, upperMatches) in [(start.addingTimeInterval(-1), false, true), (start, true, true), (end.addingTimeInterval(-1), true, true), (end, true, false)] {
                var note = Note(createdAt: .distantPast, modifiedAt: .distantPast)
                switch field {
                case "created": note.createdAt = date
                case "modified": note.modifiedAt = date
                default: note.accessedAt = date
                }
                #expect(lower.matchesScriptFilters(note, calendar: calendar) == lowerMatches)
                #expect(upper.matchesScriptFilters(note, calendar: calendar) == upperMatches)
            }
        }
    }

    @Test func relativeDaysUseCalendarDaysAndNoneDisablesTheFilter() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12)))
        for days in [-3, 0, 7] {
            let target = try #require(calendar.date(byAdding: .day, value: days, to: now))
            let boundary = calendar.startOfDay(for: target)
            let value = try workspace(["type": "relative", "field": "modified", "days": days], key: "startDate")
            #expect(value.matchesScriptFilters(Note(modifiedAt: boundary), now: now, calendar: calendar))
            #expect(!value.matchesScriptFilters(Note(modifiedAt: boundary.addingTimeInterval(-1)), now: now, calendar: calendar))
        }
        let disabled = try workspace(["type": "none", "field": "accessed", "days": 7], key: "startDate")
        #expect(disabled.matchesScriptFilters(Note(accessedAt: nil), now: now, calendar: calendar))
        let active = try workspace(["type": "relative", "field": "accessed", "days": 0], key: "startDate")
        #expect(!active.matchesScriptFilters(Note(accessedAt: nil), now: now, calendar: calendar))
    }
}
