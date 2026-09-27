import RENNDomain

/// Records telemetry events that passed the consent gate, for assertions.
public actor RecordingTelemetrySink: TelemetrySink {
    public struct Sent: Sendable, Equatable {
        public let name: String
        public let parameters: [String: String]
    }

    public private(set) var sent: [Sent] = []

    public init() {}

    public func send(name: String, parameters: [String: String]) async {
        sent.append(Sent(name: name, parameters: parameters))
    }
}

/// Telemetry that records every event without a consent gate. Tests only.
public actor RecordingTelemetry: TelemetryRecording {
    public private(set) var events: [TelemetryEvent] = []

    public init() {}

    public func record(_ event: TelemetryEvent) async {
        events.append(event)
    }
}

public struct FixedCaptureCapabilities: CaptureCapabilityProviding {
    public let availability: DualCameraAvailability

    public init(_ availability: DualCameraAvailability) {
        self.availability = availability
    }

    public func dualCameraAvailability() -> DualCameraAvailability { availability }
}

public struct StaticLookCatalogProvider: LookCatalogProviding {
    private let result: Result<LookCatalog, LookCatalog.ValidationError>

    public init(_ catalog: LookCatalog) {
        result = .success(catalog)
    }

    public init(failure: LookCatalog.ValidationError) {
        result = .failure(failure)
    }

    public func catalog() async throws -> LookCatalog {
        try result.get()
    }

    /// A single diagnostic development Look, mirroring the bundled development manifest.
    public static let developmentCatalog: LookCatalog = try! LookCatalog(
        catalogVersion: "dev-0",
        isDevelopmentFixture: true,
        recommendedLookID: "dev.diagnostic",
        looks: [
            LookDefinition(
                id: "dev.diagnostic",
                version: 1,
                family: "diagnostic",
                nameKey: "look.dev.diagnostic.name",
                descriptionKey: "look.dev.diagnostic.description",
                defaultIntensity: LookIntensity(0.7)!,
                renderVersion: 1,
                isDevelopmentFixture: true,
                lut: "dev_warm",
                parameters: [
                    LookParameter.lutMix: 0.6, LookParameter.saturation: -0.35, LookParameter.contrast: 0.08,
                    LookParameter.warmth: 1400, LookParameter.vignette: 0.7, LookParameter.grain: 0.1,
                ])
        ])
}
