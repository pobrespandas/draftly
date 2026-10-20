import Foundation
import Testing
@testable import DraftlyCore

@Suite("Syntax scripting API") @MainActor
struct SyntaxActionAPITests {
    @Test func editorLinksAndMarkersExposeTheDocumentedFields() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        editor.setText('# One\n[[note]] https://example.com\n## Two');
        const link=editor.linkedItems[0];check(link.location===6 && link.length===8 && link.value==='note','link fields');
        check(editor.urls.includes('https://example.com') && draft.urls.includes('https://example.com'),'detected URLs');
        check(editor.navigationMarkerAfter(0).label==='Two','next marker');
        check(editor.navigationMarkerBefore(2).label==='One','previous marker');
        editor.setSelectedRange(6,8);check(draft.selectionStart===6 && draft.selectionLength===8,'draft selection');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func taskPaperTasksUseTheirOwnStateRanges() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        draft.syntax='TaskPaper';draft.content='Project:\n- First\n- Second @done';draft.update();
        check(draft.tasks.length===2 && draft.completedTasks.length===1,'TaskPaper states');
        draft.completeTask(draft.tasks[0]);check(draft.completedTasks.length===2,'complete TaskPaper');
        draft.resetTask(draft.tasks[0]);check(draft.incompleteTasks.length===1,'reset TaskPaper');
        draft.update();editor.advanceTask(editor.tasks[0]);check(editor.completedTasks.length===2,'editor TaskPaper');
        check(draft.navigationMarkers[0].label==='Project','TaskPaper project');
        draft.syntax='Plain Text';check(draft.tasks.length===0 && draft.navigationMarkers.length===0,'plain text syntax');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func editorTasksAndLineRangesUseUTF16() throws {
        let (_, editor, _, runner) = try makeAPIContext("# Heading\n- [ ] Café 😀\n- [x] Done\nTail")
        #expect(runner.run(makeAPIAction(#"""
        check(editor.tasks.length === 2 && editor.incompleteTasks.length === 1, 'task parsing');
        check(editor.navigationMarkers.length === 1 && draft.navigationMarkers[0].location === 0, 'navigation markers');
        let task = editor.incompleteTasks[0]; editor.completeTask(task);
        check(editor.completedTasks.length === 2, 'task completion');
        editor.setSelectedRange(task.labelRange[0],task.labelRange[1]);
        check(editor.getSelectedText() === 'Café 😀', 'UTF16 task range');
        check(editor.getSelectedLineRange()[0] === 10, 'line range');
        let d = Draft.create(); d.content = 'Next'; d.update(); editor.load(d);
        check(editor.recentDrafts[0].displayTitle === 'Heading', 'recent drafts');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(editor.content == "Next")
    }
}
