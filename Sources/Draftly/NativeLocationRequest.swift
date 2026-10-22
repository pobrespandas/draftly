import CoreLocation
import Foundation
import DraftlyCore

@MainActor
protocol NativeLocationDriving: AnyObject {
    var servicesEnabled: Bool { get }
    var authorizationStatus: CLAuthorizationStatus { get }
    var onAuthorization: ((CLAuthorizationStatus) -> Void)? { get set }
    var onLocation: ((Double, Double) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    func requestAuthorization()
    func startUpdating()
    func stopUpdating()
    func invalidate()
}

@MainActor
final class NativeLocationRequest {
    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private let cancellation = CancellationState()
    private let now: @MainActor () -> Date
    private var deadline = Date.distantFuture
    private let driver: any NativeLocationDriving
    private var continuation: CheckedContinuation<[String: Double], Error>?
    private var timeoutTask: Task<Void, Never>?
    private var authorizationRequested = false
    private var updatesStarted = false

    init(driver: any NativeLocationDriving, now: @escaping @MainActor () -> Date = Date.init) {
        self.driver = driver; self.now = now
    }

    static func current(timeout: TimeInterval = 30,
                        driver: (any NativeLocationDriving)? = nil,
                        now: @escaping @MainActor () -> Date = Date.init) async throws -> [String: Double] {
        guard timeout.isFinite, timeout > 0 else {
            throw DraftlyError.message("The location timeout must be positive and finite.")
        }
        try Task.checkCancellation()
        let request = NativeLocationRequest(driver: driver ?? CoreLocationDriver(), now: now)
        let result = try await request.run(timeout: timeout)
        try Task.checkCancellation()
        return result
    }

    private func run(timeout: TimeInterval) async throws -> [String: Double] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError())); return }
                deadline = now().addingTimeInterval(timeout)
                driver.onAuthorization = { [weak self] status in self?.authorizationChanged(status) }
                driver.onLocation = { [weak self] latitude, longitude in
                    guard latitude.isFinite, longitude.isFinite,
                          (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                        self?.finish(.failure(DraftlyError.message("The location coordinates are invalid.")))
                        return
                    }
                    self?.finish(.success(["latitude": latitude, "longitude": longitude]))
                }
                driver.onFailure = { [weak self] error in self?.finish(.failure(error)) }
                timeoutTask = Task { @MainActor [self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    finish(.failure(ActionExecutionInterruption.timeout))
                }
                guard driver.servicesEnabled else {
                    finish(.failure(DraftlyError.message("Location services are unavailable on this Mac.")))
                    return
                }
                authorizationChanged(driver.authorizationStatus)
            }
        } onCancel: { [cancellation] in
            cancellation.cancel()
            Task { @MainActor [self] in finish(.failure(CancellationError())) }
        }
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        guard continuation != nil else { return }
        guard !cancellation.isCancelled else {
            finish(.failure(CancellationError()))
            return
        }
        guard now() < deadline else {
            finish(.failure(ActionExecutionInterruption.timeout))
            return
        }
        switch status {
        case .notDetermined:
            guard !authorizationRequested else { return }
            authorizationRequested = true
            driver.requestAuthorization()
        case .denied, .restricted:
            finish(.failure(DraftlyError.message("Location access is denied.")))
        case .authorizedAlways:
            guard !updatesStarted else { return }
            updatesStarted = true
            driver.startUpdating()
        @unknown default:
            finish(.failure(DraftlyError.message("The location authorization status is unavailable.")))
        }
    }

    private func finish(_ result: Result<[String: Double], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        driver.stopUpdating()
        driver.invalidate()
        if cancellation.isCancelled { continuation.resume(throwing: CancellationError()) }
        else if now() >= deadline { continuation.resume(throwing: ActionExecutionInterruption.timeout) }
        else { continuation.resume(with: result) }
    }
}

@MainActor
private final class CoreLocationDriver: NSObject, NativeLocationDriving, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onAuthorization: ((CLAuthorizationStatus) -> Void)?
    var onLocation: ((Double, Double) -> Void)?
    var onFailure: ((Error) -> Void)?
    var servicesEnabled: Bool { CLLocationManager.locationServicesEnabled() }
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestAuthorization() { manager.requestWhenInUseAuthorization() }
    func startUpdating() { manager.startUpdatingLocation() }
    func stopUpdating() { manager.stopUpdatingLocation() }
    func invalidate() {
        manager.delegate = nil
        onAuthorization = nil; onLocation = nil; onFailure = nil
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorization?(manager.authorizationStatus)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocation?(location.coordinate.latitude, location.coordinate.longitude)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { onFailure?(error) }
}
