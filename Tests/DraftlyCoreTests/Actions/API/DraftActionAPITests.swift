import Foundation
import Testing
@testable import DraftlyCore

@Suite("Draft scripting API") @MainActor
struct DraftActionAPITests {
    @Test func draftAddTagNormalizesUnicodeAndAvoidsDuplicates() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();check(d.addTag(' CAFE\u0301 ')===undefined,'void');d.addTag('café');d.addTag('');d.addTag('  ');
        check(d.tags.join(',')==='café','normalized unique nonempty tags');
        d.addTag('work/project');check(d.tags.includes('work/project'),'hierarchical tag preserved');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftHasTagUsesNormalizedExactNames() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();check(d.hasTag('missing')===false,'empty tags');d.tags=['café','work/project'];
        check(d.hasTag(' CAFE\u0301 ')===true,'normalized match');check(d.hasTag('work')===false,'exact name');
        check(d.hasTag('work/project')===true && d.hasTag('')===false,'present and absent');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftRemoveTagRemovesOnlyNormalizedMatchesAndReturnsVoid() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();d.tags=['café','CAFE\u0301','other'];check(d.removeTag(' CAFÉ ')===undefined,'void');
        check(d.tags.join(',')==='other','remove all matching variants');d.removeTag('missing');check(d.tags.join(',')==='other','missing is no-op');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftTagsPersistNormalizedValuesWithoutImplicitSaving() throws {
        let (library, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();d.content='Tag contract';d.tags=[' Zebra ','CAFÉ','cafe\u0301',''];
        check(Draft.queryByTitle('Tag contract').length===0,'not saved implicitly');d.update();
        check(Draft.find(d.uuid).tags.join(',')==='café,zebra','normalized persisted values');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.content == "Tag contract" }?.tags == ["café", "zebra"])
    }

    @Test func draftAppendUsesLineFeedOrExplicitSeparatorAndReturnsVoid() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();d.content='First';check(d.append('Café 🐼')===undefined,'void');
        check(d.content==='First\nCafé 🐼','default LF');d.append('tail','|');check(d.content.endsWith('🐼|tail'),'custom separator');
        d.content='';d.append('empty','');check(d.content==='empty','empty separator');
        d.content='';d.append('text');check(d.content==='\ntext','empty content keeps separator');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftPrependUsesLineFeedOrExplicitSeparatorAndReturnsVoid() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();d.content='Last';check(d.prepend('Café 🐼')===undefined,'void');
        check(d.content==='Café 🐼\nLast','default LF');d.prepend('head','|');check(d.content==='head|Café 🐼\nLast','custom separator');
        d.content='';d.prepend('empty','');check(d.content==='empty','empty separator');
        d.content='';d.prepend('text');check(d.content==='text\n','empty content keeps separator');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftInsertUsesZeroBasedLinesAndClampsOutsideIndices() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();d.content='A\nB';check(d.insert('🐼',1)===undefined,'void');
        check(d.content==='A\n🐼\nB','zero-based insertion');d.insert('Start',-9);d.insert('End',999);
        check(d.content==='Start\nA\n🐼\nB\nEnd','range checking');
        d.content='';d.insert('First',0);check(d.content==='First\n','empty line retained');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftLinesUsesLiteralLineFeedIncludingEmptyLines() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();check(JSON.stringify(d.lines)==='[""]','empty content');
        d.content='A\r\n🐼\n\n';check(JSON.stringify(d.lines)===JSON.stringify(['A\r','🐼','','']),'literal LF');
        const lines=d.lines;lines[0]='Changed';check(d.content.startsWith('A\r'),'derived array');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftLinesWithPrefixUsesCaseSensitiveLiteralPrefixes() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();d.content='Tag one\ntag two\nTag 🐼\n';
        check(JSON.stringify(d.linesWithPrefix('Tag'))===JSON.stringify(['Tag one','Tag 🐼']),'literal prefix');
        check(d.linesWithPrefix('missing').length===0,'no match');check(d.linesWithPrefix('').length===4,'empty prefix');
        check(d.linesWithPrefix('🐼').length===0,'prefix not substring');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftBodyPreviewExcludesTitleTrimsAndLimitsLength() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const d=Draft.create();check(d.bodyPreview(10)==='','empty');d.content='Only title';check(d.bodyPreview(10)==='','no body');
        d.content='Title\n  Café\nSecond  ';check(d.bodyPreview(100)==='Café Second','body trimmed and flattened');
        check(d.bodyPreview(4)==='Café' && d.bodyPreview(0)==='','length limit');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func draftConveniencesMetadataAndTemplateContracts() throws {
        let (library, editor, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const id=draft.uuid;check(typeof id==='string' && draft.permalink==='draftly://open?uuid='+id,'identity');
        check(draft.createdAt instanceof Date && draft.modifiedAt instanceof Date,'dates');
        check(draft.createdLatitude===0 && draft.createdLongitude===0 && draft.modifiedLatitude===0 && draft.modifiedLongitude===0,'location defaults');
        const d=new Draft();d.content='Title\nBody';d.append('End');d.prepend('Start','|');d.insert('Middle',1);
        check(d.lines[0]==='Start|Title' && d.lines[1]==='Middle','content helpers');
        check(d.linesWithPrefix('Bo')[0]==='Body' && d.bodyPreview(6)==='Middle','body helpers');
        d.tags=['one'];d.addTag(' ONE ');d.addTag('two');d.removeTag('ONE');check(d.tags.join(',')==='two','tags');
        d.isFlagged=true;check(d.isFlagged && d.flagType>0,'flag boolean');d.isFlagged=false;check(d.flagType===0,'clear flag');
        d.languageGrammar='Markdown';check(d.syntax instanceof Syntax,'legacy syntax');
        d.content='# Heading\n[[url:https://example.com]]\n- [ ]task';
        const link=d.linkedItems[0];check(link.key==='url' && link.value==='https://example.com' && link.prefix==='[[' && link.suffix===']]','link shape');
        check(link.location===10 && link.length===27,'link UTF16 range');
        check(d.navigationMarkers[0].prefix==='H1' && d.navigationMarkerAfter(-1).label==='Heading','marker shape');
        check(d.navigationMarkerBefore(1).location===0,'marker before');
        check(d.tasks[0].interactive==='[ ]' && d.tasks[0].label==='task','task shape');
        d.completeTask(d.tasks[0]);check(d.completedTasks.length===1,'complete');d.resetTask(d.tasks[0]);d.advanceTask(d.tasks[0]);
        check(d.incompleteTasks.length===0,'toggle');
        d.setTemplateTag('custom','café');check(d.getTemplateTag('custom')==='café','custom tag');
        check(d.processTemplate('[[custom]]')==='café' && d.processMustacheTemplate('{{custom}}')==='café','both template engines');
        d.update();d.saveVersion();check(d.versions.length>0,'versions');
        check(Draft.find(d.uuid)===d && typeof d.toJSON().content==='string','serialization');
        check(Array.isArray(Draft.recentTags()) && Array.isArray(d.actionLogs),'related records');
        editor.setSelectedRange(2,3);editor.save();editor.new();editor.load(Draft.find(id));
        check(editor.getSelectedRange().join(',')==='2,3' && editor.recentDrafts.length>0,'saved selection');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.contains { $0.id == editor.noteID })
    }

    @Test func draftMetadataDatesSyntaxAndQueriesRoundTrip() throws {
        let (library, _, _, runner) = try makeAPIContext()
        let source = #"""
        let d = Draft.create();
        d.content = '# Meeting\nNotes'; d.addTag(' WORK '); d.flagType = 5;
        d.createdAt = new Date('2020-01-02T03:04:05Z'); d.modifiedAt = new Date('2021-02-03T04:05:06Z');
        d.syntax = Syntax.find('builtIn','Markdown'); d.createdLatitude = 12.5; d.createdLongitude=45;d.modifiedLatitude=11;d.modifiedLongitude=22; d.folder = 'archive'; d.update();
        check(d.title === '# Meeting' && d.displayTitle === 'Meeting', 'titles');
        let found = Draft.queryByTitle('meet')[0];
        check(found.createdAt instanceof Date && found.modifiedAt.getUTCFullYear() === 2021, 'dates');
        check(found.syntax.name === 'Markdown' && found.flagType === 5 && found.folder === 'archive', 'metadata');
        check(found.hasTag('Work') && found.createdLatitude === 12.5 && found.createdLongitude===45 && found.modifiedLatitude===11 && found.modifiedLongitude===22, 'tags and location');
        check(Draft.flagged('blue').length === 1, 'flag query');
        found.folder = 'trash'; found.update();
        check(Draft.query('', 'trash').length === 1, 'trash query');
        """#
        #expect(runner.run(makeAPIAction(source)), Comment(rawValue: runner.message ?? ""))
        #expect(library.notes.first { $0.title == "Meeting" }?.trashedAt != nil)
    }
}
