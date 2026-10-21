import Foundation
import Testing
@testable import DraftlyCore

@Suite("Workspace query date boundaries")
struct WorkspaceDateBoundaryContractTests {
    @Test(arguments: ["2026-03-08", "2026-11-01"], ["created", "modified", "accessed"])
    func absoluteAndRelativeDatesUseInclusiveCalendarDays(day: String, field: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let pieces = day.split(separator: "-").compactMap { Int($0) }
        let noon = try #require(calendar.date(from: DateComponents(
            year: pieces[0], month: pieces[1], day: pieces[2], hour: 12, minute: 30)))
        let start = calendar.startOfDay(for: noon)
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(end.timeIntervalSince(start) == (day == "2026-03-08" ? 23 : 25) * 3600)
        let dates = [start.addingTimeInterval(-0.001), start, end.addingTimeInterval(-0.001), end]
        let notes = dates.map { date in
            Note(content: "Neutral café 🐼", createdAt: date, modifiedAt: date, accessedAt: date)
        }
        for (type, days) in [("absolute", 0), ("relative", -1), ("relative", 1)] {
            let now = try #require(calendar.date(byAdding: .day, value: -days, to: noon))
            for key in ["startDate", "endDate"] {
                var workspace = Workspace(name: "Inclusive date")
                let query: [String: Any] = ["type": type, "field": field, "days": days,
                                            "date": APIValues.date(noon)]
                let data = try JSONSerialization.data(withJSONObject: [key: query])
                workspace.scriptMetadata = ["api": String(decoding: data, as: UTF8.self)]
                let actual = notes.map { workspace.matchesScriptFilters($0, now: now, calendar: calendar) }
                let expected = key == "startDate" ? [false, true, true, true] : [true, true, true, false]
                #expect(actual == expected, "\(key) \(type) days=\(days) \(field) \(day)")
                if field == "accessed" {
                    let unknown = Note(content: "Unknown access")
                    #expect(!workspace.matchesScriptFilters(unknown, now: now, calendar: calendar))
                    #expect(unknown.accessedAt == nil)
                }
            }
        }
    }
}
