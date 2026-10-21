import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action group identity allocation")
struct ActionGroupIdentityTests {
    private let first = "B" + String(repeating: "A", count: 16)
    private let second = "?" + String(repeating: "A", count: 15)

    @Test func legacyIdentifiersStayCompatibleWhileCollidingNamesGetDistinctIDs() {
        let legacy = ActionGroupRecord.identifier(for: first)
        #expect(legacy.uuidString == "3F414141-4141-4141-4141-414141414141")
        #expect(ActionGroupRecord.identifier(for: second) == legacy)
        #expect(ActionGroupRecord(name: first).id == legacy)
        #expect(ActionGroupRecord(name: second).id == legacy)
        let forward = ActionGroupIdentity.identifiers(names: [first, second], records: [])
        let reverse = ActionGroupIdentity.identifiers(names: [second, first], records: [])
        #expect(forward == reverse)
        #expect(Set(forward.values).count == 2)
        #expect(forward[second] == legacy)
        #expect(forward[first] != legacy)
        #expect(ActionGroupIdentity.collisionNames(names: [first, second], records: []) == [first, second])
    }

    @Test func storedIDsAreReservedBeforePreferredAndLegacyIDs() throws {
        let legacy = ActionGroupRecord.identifier(for: first)
        var stored = ActionGroupRecord(name: "Stored")
        stored.id = legacy
        let result = ActionGroupIdentity.identifiers(names: [first, "Preferred"], records: [stored],
            preferred: ["Preferred": legacy])
        #expect(result[stored.name] == legacy)
        #expect(result[first] != legacy && result["Preferred"] != legacy)
        #expect(Set(result.values).count == 3)
        #expect(ActionGroupIdentity.collisionNames(names: [first], records: [stored]) == [first])
        #expect(result == ActionGroupIdentity.identifiers(names: ["Preferred", first], records: [stored],
            preferred: ["Preferred": legacy]))
    }

    @Test func preferredIDsAreAllocatedBeforeUnpreferredLegacyCandidates() {
        let legacyName = "Legacy candidate"
        let preferredID = ActionGroupRecord.identifier(for: legacyName)
        let result = ActionGroupIdentity.identifiers(names: [legacyName, "Preferred"], records: [],
            preferred: ["Preferred": preferredID])
        #expect(result["Preferred"] == preferredID)
        #expect(result[legacyName] != preferredID)
        #expect(Set(result.values).count == 2)
        #expect(result == ActionGroupIdentity.identifiers(names: ["Preferred", legacyName], records: [],
            preferred: ["Preferred": preferredID]))
    }

    @Test func firstStoredNameWinsAndUnoccupiedPreferredIDsRemainStable() throws {
        let firstID = try #require(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        let unusedID = try #require(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        var kept = ActionGroupRecord(name: "Repeated")
        kept.id = firstID
        var ignored = ActionGroupRecord(name: "Repeated")
        ignored.id = unusedID
        let result = ActionGroupIdentity.identifiers(names: ["Repeated", "Preferred"], records: [kept, ignored],
            preferred: ["Repeated": unusedID, "Preferred": unusedID])
        #expect(result["Repeated"] == firstID)
        #expect(result["Preferred"] == unusedID)
        #expect(result.count == 2)
        #expect(ActionGroupIdentity.collisionNames(names: ["Repeated", "Preferred"], records: [kept, ignored]).isEmpty)
    }

    @Test func occupiedHashCandidateAdvancesDeterministically() throws {
        let baseline = ActionGroupIdentity.identifiers(names: [first, second], records: [])
        let occupied = try #require(baseline[first])
        var record = ActionGroupRecord(name: "Reserved hash")
        record.id = occupied
        let result = ActionGroupIdentity.identifiers(names: [first, second], records: [record])
        #expect(result[record.name] == occupied)
        #expect(result[first] != occupied && result[first] != result[second])
        #expect(Set(result.values).count == 3)
        #expect(result == ActionGroupIdentity.identifiers(names: [second, first], records: [record]))
    }

    @Test func preferredCollisionsUseSortedNamePriority() throws {
        let preferred = try #require(UUID(uuidString: "33333333-3333-4333-8333-333333333333"))
        let values = ["Zulu": preferred, "Alpha": preferred]
        let result = ActionGroupIdentity.identifiers(names: ["Zulu", "Alpha"], records: [], preferred: values)
        #expect(result["Alpha"] == preferred)
        #expect(result["Zulu"] != preferred)
        #expect(result == ActionGroupIdentity.identifiers(names: ["Alpha", "Zulu"], records: [], preferred: values))
    }
}
