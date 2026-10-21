import Foundation
import Testing
@testable import DraftlyCore

@Suite("Draft and Editor URL contracts") @MainActor
struct DraftURLContractTests {
    @Test(arguments: [false, true])
    func fullCustomURLsAreReturnedAlongsideHTTPS(worker: Bool) async throws {
        let (_, _, _, runner) = try makeAPIContext()
        let action = makeAPIAction(#"""
        const expected=['https://example.com/path?q=caf%C3%A9','draftly://open?uuid=neutral','shortcuts://run-shortcut?name=Neutral%20test','tel:+15555550123','mailto:neutral@example.com'];
        editor.setText('🐼 '+expected.join('\n'));
        check(JSON.stringify(editor.urls)===JSON.stringify(expected),'editor full custom URLs');
        check(JSON.stringify(draft.urls)===JSON.stringify(expected),'draft full custom URLs');
        const detached=Draft.create();detached.content='🐼 '+expected[1]+' '+expected[1];
        check(JSON.stringify(detached.urls)===JSON.stringify([expected[1],expected[1]]),'detached duplicate URL occurrences');
        check(JSON.stringify(editor.urls)===JSON.stringify(expected),'detached read leaves editor unchanged');
        detached.content='No URL here 🐼';check(detached.urls.length===0,'no URLs gives empty array');
        editor.setText('');check(editor.urls.length===0 && draft.urls.length===0,'empty editor and draft arrays');
        """#)
        if worker { #expect(await runner.runAsync(action).reason == .success, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
    }
}
