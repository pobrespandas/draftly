import CoreLocation
import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous location requests")
@MainActor
struct NativeLocationRequestTests {
    @Test func authorizedLocationReturnsTheCoordinateContractAndStopsUpdating() async throws {
        let driver = LocationDriverFixture()
        driver.whenStarted = { driver.onLocation?(-34.6, -58.4) }
        let result = try await NativeLocationRequest.current(driver: driver)
        #expect(result == ["latitude": -34.6, "longitude": -58.4])
        #expect(driver.authorizationRequests == 0)
        #expect(driver.starts == 1)
        #expect(driver.stops == 1)
        #expect(driver.invalidated)
        #expect(driver.onLocation == nil)
    }

    @Test func unknownAuthorizationRequestsPermissionBeforeStartingUpdates() async throws {
        let driver = LocationDriverFixture()
        driver.authorizationStatus = .notDetermined
        driver.whenAuthorizationRequested = {
            #expect(driver.starts == 0)
            driver.onAuthorization?(.notDetermined)
            driver.authorizationStatus = .authorizedAlways
            driver.onAuthorization?(.authorizedAlways)
            driver.onAuthorization?(.authorizedAlways)
        }
        driver.whenStarted = { driver.onLocation?(1, 2) }
        let result = try await NativeLocationRequest.current(driver: driver)
        #expect(result["latitude"] == 1)
        #expect(driver.authorizationRequests == 1)
        #expect(driver.starts == 1)
    }

    @Test func deniedAndRestrictedAuthorizationDoNotRequestOrStart() async {
        for status in [CLAuthorizationStatus.denied, .restricted] {
            let driver = LocationDriverFixture()
            driver.authorizationStatus = status
            do { _ = try await NativeLocationRequest.current(driver: driver); Issue.record("Denied location access succeeded.") }
            catch { #expect(error.localizedDescription == "Location access is denied.") }
            #expect(driver.authorizationRequests == 0)
            #expect(driver.starts == 0)
            #expect(driver.invalidated)
        }
    }

    @Test func disabledServicesFailWithoutAuthorizationOrUpdates() async {
        let driver = LocationDriverFixture()
        driver.servicesEnabled = false
        do { _ = try await NativeLocationRequest.current(driver: driver); Issue.record("Disabled location services succeeded.") }
        catch { #expect(error.localizedDescription == "Location services are unavailable on this Mac.") }
        #expect(driver.authorizationRequests == 0)
        #expect(driver.starts == 0)
        #expect(driver.invalidated)
    }

    @Test func driverFailureIsPreservedAndResourcesAreStopped() async {
        let driver = LocationDriverFixture()
        driver.whenStarted = { driver.onFailure?(NSError(domain: "Draftly.LocationFixture", code: 42, userInfo: [NSLocalizedDescriptionKey: "Neutral location failure"])) }
        do { _ = try await NativeLocationRequest.current(driver: driver); Issue.record("The location error succeeded.") }
        catch { #expect(error.localizedDescription == "Neutral location failure") }
        #expect(driver.stops == 1)
        #expect(driver.invalidated)
    }

    @Test func cancellationStopsUpdatesAndRejectsLateCallbacks() async throws {
        let driver = LocationDriverFixture()
        let task = Task { try await NativeLocationRequest.current(driver: driver) }
        var started = driver.started.stream.makeAsyncIterator()
        try #require(await started.next() == true)
        let lateLocation = driver.onLocation
        let lateAuthorization = driver.onAuthorization
        task.cancel()
        do { _ = try await task.value; Issue.record("The cancelled location request succeeded.") }
        catch { #expect(error is CancellationError) }
        lateLocation?(3, 4)
        lateAuthorization?(.authorizedAlways)
        #expect(driver.starts == 1)
        #expect(driver.stops == 1)
        #expect(driver.invalidated)
    }

    @Test func cancellationRejectsAuthorizationBeforeQueuedCleanup() async throws {
        let driver = LocationDriverFixture()
        driver.authorizationStatus = .notDetermined
        let task = Task { try await NativeLocationRequest.current(driver: driver) }
        var requested = driver.authorizationRequested.stream.makeAsyncIterator()
        try #require(await requested.next() == true)
        task.cancel()
        driver.onAuthorization?(.authorizedAlways)
        driver.onLocation?(3, 4)
        do { _ = try await task.value; Issue.record("The cancelled authorization succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(driver.starts == 0)
        #expect(driver.stops == 1)
        #expect(driver.invalidated)
    }

    @Test func authorizationWaitTimesOutWithoutStartingLocationUpdates() async {
        let driver = LocationDriverFixture()
        driver.authorizationStatus = .notDetermined
        do { _ = try await NativeLocationRequest.current(timeout: 0.02, driver: driver); Issue.record("The location authorization did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(driver.authorizationRequests == 1)
        #expect(driver.starts == 0)
        #expect(driver.invalidated)
    }

    @Test(arguments: [false, true], [false, true])
    func expiredAuthorizationAndCoordinatesCannotBeatQueuedTimeout(authorization: Bool, exactDeadline: Bool) async {
        let driver = LocationDriverFixture()
        var now = Date(timeIntervalSinceReferenceDate: 100)
        if authorization {
            driver.authorizationStatus = .notDetermined
            driver.whenAuthorizationRequested = {
                now = now.addingTimeInterval(exactDeadline ? 10 : 11)
                driver.onAuthorization?(.authorizedAlways)
            }
        }
        driver.whenStarted = {
            if !authorization { now = now.addingTimeInterval(exactDeadline ? 10 : 11) }
            driver.onLocation?(1, 2)
        }
        do {
            _ = try await NativeLocationRequest.current(timeout: 10, driver: driver, now: { now })
            Issue.record("Expired location returned coordinates.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        #expect(driver.starts == (authorization ? 0 : 1))
        #expect(driver.stops == 1 && driver.invalidated)
    }

    @Test func invalidCoordinatesFailExplicitly() async {
        let driver = LocationDriverFixture()
        driver.whenStarted = { driver.onLocation?(.nan, 200) }
        do { _ = try await NativeLocationRequest.current(driver: driver); Issue.record("Invalid coordinates succeeded.") }
        catch { #expect(error.localizedDescription == "The location coordinates are invalid.") }
        #expect(driver.invalidated)
    }

    @Test func invalidTimeoutDoesNotStartTheDriver() async {
        let driver = LocationDriverFixture()
        do { _ = try await NativeLocationRequest.current(timeout: 0, driver: driver); Issue.record("The invalid timeout succeeded.") }
        catch { #expect(error.localizedDescription == "The location timeout must be positive and finite.") }
        #expect(driver.starts == 0)
        #expect(driver.authorizationRequests == 0)
    }
}

@MainActor
private final class LocationDriverFixture: NativeLocationDriving {
    let authorizationRequested = AsyncStream.makeStream(of: Bool.self)
    let started = AsyncStream.makeStream(of: Bool.self)
    var servicesEnabled = true
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var onAuthorization: ((CLAuthorizationStatus) -> Void)?
    var onLocation: ((Double, Double) -> Void)?
    var onFailure: ((Error) -> Void)?
    var whenStarted: (() -> Void)?
    var whenAuthorizationRequested: (() -> Void)?
    var authorizationRequests = 0
    var starts = 0
    var stops = 0
    var invalidated = false

    func requestAuthorization() { authorizationRequests += 1; authorizationRequested.continuation.yield(true); authorizationRequested.continuation.finish(); whenAuthorizationRequested?() }
    func startUpdating() { starts += 1; started.continuation.yield(true); started.continuation.finish(); whenStarted?() }
    func stopUpdating() { stops += 1 }
    func invalidate() {
        started.continuation.finish()
        authorizationRequested.continuation.finish()
        invalidated = true; onAuthorization = nil; onLocation = nil; onFailure = nil
        whenStarted = nil; whenAuthorizationRequested = nil
    }
}
