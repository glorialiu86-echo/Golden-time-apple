import Foundation
#if os(iOS) || os(watchOS)
@preconcurrency import WatchConnectivity

private enum GTWatchSyncPayload {
    static let languagePreferenceKey = GTAppLanguage.storageKey
    static let languageEffectiveKey = GTAppLanguage.effectiveMirrorKey
    static let twilightModeKey = GTTwilightDisplayMode.storageKey
    static let mapCameraDistanceKey = GTCompassMapSettings.storageKey

    static func applicationContext(
        languagePreferenceRaw: String,
        effectiveLanguageRaw: String,
        twilightModeRaw: String,
        mapCameraDistance: Double
    ) -> [String: Any] {
        [
            languagePreferenceKey: languagePreferenceRaw,
            languageEffectiveKey: effectiveLanguageRaw,
            twilightModeKey: twilightModeRaw,
            mapCameraDistanceKey: mapCameraDistance
        ]
    }

    static func apply(_ applicationContext: [String: Any], to store: UserDefaults) {
        if let raw = applicationContext[languagePreferenceKey] as? String {
            store.set(raw, forKey: languagePreferenceKey)
        }
        if let raw = applicationContext[languageEffectiveKey] as? String {
            store.set(raw, forKey: languageEffectiveKey)
        }
        if let raw = applicationContext[twilightModeKey] as? String {
            store.set(raw, forKey: twilightModeKey)
        }
        if let raw = applicationContext[mapCameraDistanceKey] as? Double, raw.isFinite, raw > 0 {
            store.set(raw, forKey: mapCameraDistanceKey)
        }
    }
}

final class GTWatchConnectivitySync: NSObject, WCSessionDelegate, @unchecked Sendable {
    nonisolated(unsafe) static let shared = GTWatchConnectivitySync()

    private let store = GTAppGroup.shared
    #if os(iOS)
    private let pendingPhoneContextLock = NSLock()
    private var pendingPhoneContext: [String: Any]?
    #endif

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil || session.delegate !== self {
            session.delegate = self
        }
        session.activate()
        #if os(watchOS)
        applyFromSessionIfAvailable(session)
        #endif
    }

    #if os(iOS)
    func pushPhoneState(
        languagePreferenceRaw: String,
        effectiveLanguageRaw: String,
        twilightModeRaw: String,
        mapCameraDistance: Double
    ) {
        let context = GTWatchSyncPayload.applicationContext(
            languagePreferenceRaw: languagePreferenceRaw,
            effectiveLanguageRaw: effectiveLanguageRaw,
            twilightModeRaw: twilightModeRaw,
            mapCameraDistance: mapCameraDistance
        )
        setPendingPhoneContext(context)
        flushPendingPhoneContextIfPossible()
    }
    #endif

    #if os(watchOS)
    private func applyFromSessionIfAvailable(_ session: WCSession) {
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        GTWatchSyncPayload.apply(context, to: store)
    }
    #endif

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        #if os(iOS)
        flushPendingPhoneContextIfPossible()
        #elseif os(watchOS)
        applyFromSessionIfAvailable(session)
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        #if os(watchOS)
        GTWatchSyncPayload.apply(applicationContext, to: store)
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    private func flushPendingPhoneContextIfPossible() {
        pendingPhoneContextLock.lock()
        defer { pendingPhoneContextLock.unlock() }
        guard let context = pendingPhoneContext else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(context)
            pendingPhoneContext = nil
        } catch {
            pendingPhoneContext = context
        }
    }

    private func setPendingPhoneContext(_ context: [String: Any]) {
        pendingPhoneContextLock.lock()
        pendingPhoneContext = context
        pendingPhoneContextLock.unlock()
    }
    #endif
}
#endif
