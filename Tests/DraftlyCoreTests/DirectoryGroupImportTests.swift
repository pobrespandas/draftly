import Foundation
import Testing
@testable import DraftlyCore

@Suite("Directory action group import")
struct DirectoryGroupImportTests {
    @Test func directoryRejectsUntrustedHostsAndFailedResponses() async throws {
        let untrusted = try #require(URL(string: "https://example.invalid/group"))
        do {
            _ = try await ActionImporter.directoryInstallationData(untrusted) { _ in
                Issue.record("Untrusted host reached transport")
                throw DraftlyError.message("Unexpected transport")
            }
            Issue.record("An untrusted host was accepted")
        } catch { #expect(error.localizedDescription.contains("Drafts Directory")) }
        let trusted = try #require(URL(string: "https://actions.getdrafts.com/g/neutral"))
        do {
            _ = try await ActionImporter.directoryInstallationData(trusted) { request in
                (Data(), HTTPURLResponse(url: request, statusCode: 503, httpVersion: nil, headerFields: nil)!)
            }
            Issue.record("A failed response was accepted")
        } catch { #expect(error.localizedDescription.contains("could not be downloaded")) }
    }
    @Test func directoryPageRetainsTheOfficialGroupPayload() async throws {
        let file = try #require(Bundle.module.url(forResource: "drafts-directory-basic-2026-10-29.synthetic", withExtension: "draftsActionGroup", subdirectory: "Fixtures"))
        let json = try DraftsActionGroupImport.decompress(Data(contentsOf: file))
        var target = URLComponents(); target.scheme = "drafts5"; target.host = "actionGroup"
        target.queryItems = [URLQueryItem(name: "identifier", value: "1BG"), URLQueryItem(name: "data", value: String(decoding: json, as: UTF8.self))]
        let direct = try #require(target.url)
        #expect(try await ActionImporter.download(direct).count == 31)
        let link = direct.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
        let page = Data("<a href=\"\(link)\">Install</a>".utf8)
        let url = try #require(URL(string: "https://actions.getdrafts.com/g/1BG"))
        let data = try await ActionImporter.directoryInstallationData(url) { request in
            (page, HTTPURLResponse(url: request, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        #expect(backup.actionGroups?.first?.id.uuidString == "078CF5D6-AD76-419C-AF19-A7EC3236F21B")
        #expect(backup.actions.count == 31 && backup.actions.first?.name == "Copy")
        #expect(backup.actions.filter(\.isSeparator).map(\.name) == ["Services", "Apps"])
        #expect(backup.actions.allSatisfy { $0.sourceURL == url.absoluteString })
    }
}
