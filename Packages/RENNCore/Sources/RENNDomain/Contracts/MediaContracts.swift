import Foundation

// Provisional media seams declared in M00 so feature code can depend on contracts.
// M02 (media proof) finalizes these signatures with real AVFoundation adapters.

/// Identifies a validated local export output.
public struct OutputID: Sendable, Hashable, Codable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct ExportJobID: Sendable, Hashable, Codable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum ExportFailure: Error, Sendable, Equatable {
    case unsupportedSource
    case insufficientStorage
    case renderFailed
    case writerFailed
    case validationFailed
}

public enum PhotosSaveFailure: Error, Sendable, Equatable {
    case permissionDenied
    case failed
    /// Process ended after submission but before durable confirmation (05 V09).
    case uncertain
}

/// Export lifecycle (04 A05, 05 V09). Render success and Photos save are separate states.
public enum ExportJobState: Sendable, Equatable {
    case validating
    case preparing
    /// Fraction of decoded/rendered media, 0...1, measured, never fabricated.
    case rendering(progress: Double)
    case finalizing
    case savingToPhotos(OutputID)
    case completed(OutputID)
    case saveFailed(OutputID, PhotosSaveFailure)
    case failed(ExportFailure)
    case cancelled
    case interrupted
}

public protocol Exporting: Sendable {
    func startExport(projectID: ProjectID, policy: OutputPolicy) async throws(ExportFailure) -> ExportJobID
    func updates(for job: ExportJobID) async -> AsyncStream<ExportJobState>
    func cancel(_ job: ExportJobID) async
    /// Retries only the Photos save of an already committed output; never re-renders.
    func retryPhotosSave(_ output: OutputID) async
}

public enum MediaPreparationFailure: Error, Sendable, Equatable {
    case unreadable
    case noVideoTrack
    case unsupportedFormat
    case insufficientStorage
    case cancelled
}

/// A source copied into app-owned staging and inspected (05 V06).
public struct PreparedSource: Sendable, Equatable {
    /// Path relative to the app's controlled storage root; never an absolute or picker URL.
    public let relativePath: String
    public let profile: SourceMediaProfile

    public init(relativePath: String, profile: SourceMediaProfile) {
        self.relativePath = relativePath
        self.profile = profile
    }
}

public protocol MediaPreparing: Sendable {
    func prepareImport(fromTemporaryFile url: URL) async throws(MediaPreparationFailure) -> PreparedSource
}
