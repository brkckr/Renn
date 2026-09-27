import Testing
@testable import RENNDomain

private actor CountingSink: TelemetrySink {
    var count = 0
    func send(name: String, parameters: [String: String]) async { count += 1 }
}

private actor Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
    func set(_ newValue: Bool) { value = newValue }
}

@Suite("Consent-gated telemetry (06 C05)")
struct TelemetryTests {
    @Test func disabledMeansNothingIsSent() async {
        let sink = CountingSink()
        let consent = Flag(false)
        let telemetry = ConsentGatedTelemetry(isCollectionAllowed: { await consent.value }, sink: sink)
        await telemetry.record(.previewReady)
        await telemetry.record(.creationStarted(mode: .camera))
        #expect(await sink.count == 0)

        await consent.set(true)
        await telemetry.record(.previewReady)
        #expect(await sink.count == 1)
    }

    @Test func consentStatesAllowCollectionOnlyWhenGranted() {
        #expect(!DiagnosticsConsent.notAsked.allowsCollection)
        #expect(!DiagnosticsConsent.declined.allowsCollection)
        #expect(DiagnosticsConsent.granted.allowsCollection)
    }

    @Test func eventNamesMatchContract() {
        #expect(TelemetryEvent.creationStarted(mode: .importVideo).name == "creation_started")
        #expect(TelemetryEvent.exportCompleted(tier: .free, quality: .hd720, elapsedSecondsBucket: .upTo30s).name
            == "export_completed")
        #expect(TelemetryEvent.photosSaveFinished(saved: true).name == "photos_save_finished")
    }

    @Test func parametersContainOnlyAllowlistedKeys() {
        let allowed: Set<String> = [
            "mode", "duration", "look_id", "enabled", "tier", "quality", "elapsed", "stage",
            "saved", "completed", "placement", "plan", "result",
        ]
        let events: [TelemetryEvent] = [
            .creationStarted(mode: .dualCamera),
            .sourceReady(mode: .camera, duration: .upTo30s),
            .lookSelected(lookID: "dev.diagnostic"),
            .exportStarted(tier: .pro, quality: .uhd4k, duration: .upTo3m),
            .purchaseFinished(plan: .annual, result: .pending),
            .paywallShown(placement: .freeDurationLimit),
        ]
        for event in events {
            #expect(Set(event.parameters.keys).isSubset(of: allowed))
        }
    }
}
