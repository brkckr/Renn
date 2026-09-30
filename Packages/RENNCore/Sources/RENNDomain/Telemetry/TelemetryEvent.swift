/// Allowlisted, structured telemetry (06 C05). Every field is a typed enum or bucket so
/// names, paths, media, receipts and raw error strings cannot be sent by construction.
public enum TelemetryEvent: Sendable, Equatable {
    public enum CreationMode: String, Sendable { case camera, dualCamera, importVideo }
    public enum DurationBucket: String, Sendable { case upTo15s, upTo30s, upTo60s, upTo3m, upTo10m, over10m }
    public enum QualityBucket: String, Sendable { case sd, hd720, hd1080, uhd4k }
    public enum ExportStage: String, Sendable { case validating, preparing, rendering, finalizing, saving }
    public enum PurchaseResult: String, Sendable { case granted, pending, cancelled, failed }
    public enum PaywallPlacement: String, Sendable { case settings, exportUpgrade, freeDurationLimit, home }

    case creationStarted(mode: CreationMode)
    case sourceReady(mode: CreationMode, duration: DurationBucket)
    case lookSelected(lookID: LookID)
    case beatChanged(enabled: Bool)
    case previewReady
    case exportStarted(tier: AccessTier, quality: QualityBucket, duration: DurationBucket)
    case exportCompleted(tier: AccessTier, quality: QualityBucket, elapsedSecondsBucket: DurationBucket)
    case exportFailed(stage: ExportStage)
    case exportCancelled(stage: ExportStage)
    case exportInterrupted(stage: ExportStage)
    case photosSaveFinished(saved: Bool)
    case shareSheetOpened
    case shareSheetFinished(completed: Bool)
    case paywallShown(placement: PaywallPlacement)
    case purchaseStarted(plan: PurchasePlan)
    case purchaseFinished(plan: PurchasePlan, result: PurchaseResult)
    case restoreFinished(tier: AccessTier)

    public var name: String {
        switch self {
        case .creationStarted: "creation_started"
        case .sourceReady: "source_ready"
        case .lookSelected: "look_selected"
        case .beatChanged: "beat_changed"
        case .previewReady: "preview_ready"
        case .exportStarted: "export_started"
        case .exportCompleted: "export_completed"
        case .exportFailed: "export_failed"
        case .exportCancelled: "export_cancelled"
        case .exportInterrupted: "export_interrupted"
        case .photosSaveFinished: "photos_save_finished"
        case .shareSheetOpened: "share_sheet_opened"
        case .shareSheetFinished: "share_sheet_finished"
        case .paywallShown: "paywall_shown"
        case .purchaseStarted: "purchase_started"
        case .purchaseFinished: "purchase_finished"
        case .restoreFinished: "restore_finished"
        }
    }

    /// Flat, provider-neutral parameters. Adapters map these without adding fields.
    public var parameters: [String: String] {
        switch self {
        case .creationStarted(let mode): ["mode": mode.rawValue]
        case .sourceReady(let mode, let duration): ["mode": mode.rawValue, "duration": duration.rawValue]
        case .lookSelected(let lookID): ["look_id": lookID.rawValue]
        case .beatChanged(let enabled): ["enabled": String(enabled)]
        case .previewReady, .shareSheetOpened: [:]
        case .exportStarted(let tier, let quality, let duration):
            ["tier": tier.rawValue, "quality": quality.rawValue, "duration": duration.rawValue]
        case .exportCompleted(let tier, let quality, let elapsed):
            ["tier": tier.rawValue, "quality": quality.rawValue, "elapsed": elapsed.rawValue]
        case .exportFailed(let stage), .exportCancelled(let stage), .exportInterrupted(let stage):
            ["stage": stage.rawValue]
        case .photosSaveFinished(let saved): ["saved": String(saved)]
        case .shareSheetFinished(let completed): ["completed": String(completed)]
        case .paywallShown(let placement): ["placement": placement.rawValue]
        case .purchaseStarted(let plan): ["plan": plan.rawValue]
        case .purchaseFinished(let plan, let result): ["plan": plan.rawValue, "result": result.rawValue]
        case .restoreFinished(let tier): ["tier": tier.rawValue]
        }
    }
}

public protocol TelemetryRecording: Sendable {
    func record(_ event: TelemetryEvent) async
}

/// Destination for events that already passed consent (Firebase adapter in M06).
public protocol TelemetrySink: Sendable {
    func send(name: String, parameters: [String: String]) async
}

/// Consent gate: declining or not answering sends nothing (06 C05). Features never depend
/// on telemetry succeeding.
public struct ConsentGatedTelemetry: TelemetryRecording {
    private let isCollectionAllowed: @Sendable () async -> Bool
    private let sink: any TelemetrySink

    public init(isCollectionAllowed: @escaping @Sendable () async -> Bool, sink: any TelemetrySink) {
        self.isCollectionAllowed = isCollectionAllowed
        self.sink = sink
    }

    public func record(_ event: TelemetryEvent) async {
        guard await isCollectionAllowed() else { return }
        await sink.send(name: event.name, parameters: event.parameters)
    }
}

/// Sink used until Firebase is configured (M06). Drops everything.
public struct DiscardingTelemetrySink: TelemetrySink {
    public init() {}
    public func send(name: String, parameters: [String: String]) async {}
}
