import Foundation
import Testing
@testable import DraftlyCore

@Suite("Utility scripting API") @MainActor
struct UtilityActionAPITests {
    @Test func deviceUsesMacValuesAndReportsUnavailableBatteryExplicitly() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction("check(device.model==='Mac' && device.systemName==='macOS','platform');check(typeof device.systemVersion==='string' && device.systemVersion.length>0,'version');try{let level=device.batteryLevel;check(level>=0 && level<=1,'level');}catch(e){check(e.message.includes('battery level is unavailable'),'explicit unavailable');}")))
        #expect(try ScriptDevice.batteryLevel(sources: [["Type": "InternalBattery", "Current Capacity": 50.0, "Max Capacity": 100.0]]) == 0.5)
        #expect(try ScriptDevice.batteryLevel(sources: [["Type": "InternalBattery", "Current Capacity": 0.0, "Max Capacity": 100.0]]) == 0)
        let invalid: [[[String: Any]]] = [[], [["Type": "UPS", "Current Capacity": 50, "Max Capacity": 100]], [["Type": "InternalBattery", "Current Capacity": 5, "Max Capacity": 0]], [["Type": "InternalBattery", "Current Capacity": -1, "Max Capacity": 100]]]
        for values in invalid {
            #expect(throws: (any Error).self) { try ScriptDevice.batteryLevel(sources: values) }
        }
    }

    @Test func xmlrpcTransportFailureIsAnExplicitResponse() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction("let r=XMLRPC.request('invalid','example',[1]); check(!r.success && r.statusCode===0 && r.error && r.params.length===0,'transport failure');")))
    }
}
