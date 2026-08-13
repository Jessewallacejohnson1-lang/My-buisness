//
//  UserLocation.swift
//  Block Party — a one-shot user-location read.
//
//  Deliberately as minimal as LocationPermission beside it: ONE fix via
//  `requestLocation()` — no continuous updates, no stored history, no camera
//  moves. Callers ask only when a feature actually needs a position; today that
//  is the map search's distance column. Denied / unavailable / failed simply
//  returns nil and the caller renders no distance — no nagging, no error state.
//

import CoreLocation
import Foundation

@MainActor
enum UserLocation {

    /// One position fix, or nil when not authorized / the fix fails. Never
    /// prompts — authorization is LocationPermission's job.
    static func oneShot() async -> CLLocation? {
        guard LocationPermission.isAuthorized else { return nil }
        let manager = CLLocationManager()
        let box = FixDelegate()
        manager.delegate = box
        return await withCheckedContinuation { continuation in
            // Same deliberate, temporary retain cycle as LocationPermission's
            // AuthDelegate: `manager.delegate` is a WEAK reference and ARC may
            // release `box` the moment this closure returns — the callback would
            // never fire and the task would hang. The closure captures `box`;
            // the delegate nils `onFix` the instant it fires, breaking the cycle.
            box.onFix = { [box] location in
                _ = box
                continuation.resume(returning: location)
            }
            box.keepAlive = manager
            manager.requestLocation()
        }
    }
}

/// Bridges the one `requestLocation()` answer (a fix or a failure) to one
/// continuation, exactly once. CLLocationManager delivers on the run loop of the
/// thread the manager was created on — here the main actor, the same confinement
/// AuthDelegate relies on.
private final class FixDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    var onFix: ((CLLocation?) -> Void)?
    var keepAlive: CLLocationManager?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        // Fire once, then detach so a late second callback can't resume a used
        // continuation.
        let callback = onFix
        onFix = nil
        keepAlive = nil
        callback?(location)
    }
}
