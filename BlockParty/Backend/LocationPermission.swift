//
//  LocationPermission.swift
//  Block Party — the when-in-use location prompt.
//
//  GREENFIELD. Before this, the app had NO location code at all: no `CLLocationManager`,
//  no authorization request, no Mapbox location puck. `import CoreLocation` appeared in
//  17 files but only for the `CLLocationCoordinate2D` value type — every coordinate in
//  the app is curated (`MapSpots`, `KnownVenues`), and the map centres on downtown
//  St. Joseph rather than on the user.
//
//  So this deliberately does ONE thing: ask for when-in-use authorization, and report
//  whether we have it. It does not start updates, does not hold a location, and does not
//  touch the map camera. Anything that consumes a real position is a separate decision
//  that should be made when a feature actually needs it — a permission the app never uses
//  is worse than no permission.
//
//  ⚠️ `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` must be present in BOTH the
//  Debug and Release build configurations. Without it the system prompt SILENTLY never
//  appears — no error, no callback, nothing. Verified present in both.
//
//  The `@unchecked Sendable` conformance is confined to the delegate box below, which
//  only ever touches its continuation on the main actor.
//

import CoreLocation
import Foundation

@MainActor
enum LocationPermission {

    /// Current authorization, without prompting.
    static var status: CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    static var isAuthorized: Bool {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Ask once for when-in-use access. Returns whether we ended up authorized.
    ///
    /// Resolves as soon as the user answers. If the status is already decided — granted
    /// OR denied — it returns immediately without prompting, because iOS shows the system
    /// alert only once per install and a second call would hang waiting for a callback
    /// that never comes.
    static func request() async -> Bool {
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .notDetermined else {
            return isAuthorized
        }
        let box = AuthDelegate()
        manager.delegate = box
        return await withCheckedContinuation { continuation in
            // `manager.delegate` is a WEAK reference, and after this closure returns the
            // async frame has no further use for `box` — so ARC is free to release it and
            // the callback would never fire, hanging the task forever on a screen the user
            // is staring at. The closure therefore captures `box` explicitly, which is a
            // deliberate temporary retain cycle (box → onDecided → box); the delegate nils
            // `onDecided` the moment it fires, which breaks it.
            //
            // This survived a live simulator probe unhardened, but only by ARC timing —
            // an optimised build is free to release earlier. Not worth the gamble for a
            // hang with no recovery.
            box.onDecided = { [box] granted in
                _ = box
                continuation.resume(returning: granted)
            }
            box.keepAlive = manager
            manager.requestWhenInUseAuthorization()
        }
    }
}

/// Bridges `CLLocationManagerDelegate`'s callback to one continuation, exactly once.
private final class AuthDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    var onDecided: ((Bool) -> Void)?
    var keepAlive: CLLocationManager?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // The delegate fires once on assignment with the current (.notDetermined)
        // status before the user has answered — ignore that one.
        guard status != .notDetermined else { return }
        let granted = status == .authorizedWhenInUse || status == .authorizedAlways
        // Fire once, then detach so a later status change can't resume a used continuation.
        let callback = onDecided
        onDecided = nil
        keepAlive = nil
        callback?(granted)
    }
}
