import Foundation
import Testing
@testable import DraftlyCore

@Suite("Bundled user guide")
struct HelpGuideTests {
    @Test func allTopicsShipWithContentAndUniqueIdentity() throws {
        let articles = try HelpGuide.articles()
        #expect(articles.count == 18)
        #expect(Set(articles.map(\.id)).count == articles.count)
        for article in articles {
            #expect(article.markdown.hasPrefix("# " + article.title + "\n"))
            #expect(article.markdown.count > 500)
        }
    }

    @Test func agentSkillIsBundledSeparatelyFromTheUserIndex() throws {
        let skill = try HelpGuide.agentSkill()
        #expect(skill.id == "agent-skill")
        #expect(skill.markdown.hasPrefix("---\nname: draftly\n"))
        #expect(try !HelpGuide.articles().contains { $0.id == skill.id })
    }

    @Test func searchFindsContentAcrossTopicsWithoutExactPhrase() throws {
        let articles = try HelpGuide.articles()
        #expect(articles.filter { $0.matches("  UNDO editor  ") }.contains { $0.id == "04-editor" })
        #expect(articles.filter { $0.matches("notarized") }.contains { $0.id == "02-install" })
        #expect(articles.filter { $0.matches("zzzz-no-such-help-topic") }.isEmpty)
        #expect(articles.filter { $0.matches(" \n ") } == articles)
    }
}
