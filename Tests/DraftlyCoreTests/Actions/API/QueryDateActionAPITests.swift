import Foundation
import Testing
@testable import DraftlyCore

@Suite("QueryDate scripting API") @MainActor
struct QueryDateActionAPITests {
    @Test func queryDateConstructorCreatesIndependentValues() throws {
        let (_, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const before=Date.now(), a=new QueryDate(), b=new QueryDate();
        check(a instanceof QueryDate && a!==b,'independent instances');
        check(a.type==='none' && a.field==='modified' && a.days===0,'initial values');
        check(a.date instanceof Date && a.date.getTime()>=before && a.date.getTime()<=Date.now(),'current date');
        check(a.date!==b.date,'independent dates');
        a.days=-3;check(b.days===0,'no shared state');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(host.calls.isEmpty)
    }

    @Test func queryDateDatePreservesAbsoluteDateThroughStorage() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const q=new QueryDate(), stamp=new Date('2026-03-08T23:45:12.345Z');
        q.type='absolute';q.date=stamp;
        check(q.date===stamp,'Date assignment');
        const w=new Workspace();w.name='Absolute date contract';w.startDate=q;w.update();
        const restored=Workspace.find(w.name).startDate;
        check(restored instanceof QueryDate && restored.date instanceof Date,'typed restoration');
        check(restored.date.getTime()===stamp.getTime(),'absolute date precision');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func queryDateDaysPreservesNegativeZeroAndPositiveIntegers() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        for(const days of [-3,0,7]) {
            const q=new QueryDate();q.type='relative';q.days=days;
            const w=new Workspace();w.name='Relative date '+days;w.startDate=q;w.update();
            const saved=Workspace.find(w.name).startDate;
            check(saved.days===days && saved.type==='relative','relative integer '+days);
        }
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func queryDateFieldPreservesEverySupportedDateField() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        for(const field of ['created','modified','accessed']) {
            const q=new QueryDate();q.field=field;
            const w=new Workspace();w.name='Date field '+field;w.startDate=q;w.update();
            check(Workspace.find(w.name).startDate.field===field,'date field '+field);
        }
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func queryDateTypePreservesEverySupportedRangeType() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        for(const type of ['none','relative','absolute']) {
            const q=new QueryDate();q.type=type;
            const w=new Workspace();w.name='Date type '+type;w.endDate=q;w.update();
            check(Workspace.find(w.name).endDate.type===type,'date type '+type);
        }
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func queryDateFactoryReturnsFreshQueryDates() throws {
        let (_, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const a=QueryDate.create(), b=QueryDate.create();
        check(a instanceof QueryDate && !(a instanceof Workspace),'factory result');
        check(a!==b && a.date!==b.date,'fresh values');
        check(a.type==='none' && a.field==='modified' && a.days===0 && a.date instanceof Date,'factory defaults');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(host.calls.isEmpty)
    }
}
