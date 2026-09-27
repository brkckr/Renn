import Foundation

// Provisional media seams declared in M00 so feature code can depend on contracts.
// M02 (media proof) finalizes these signatures with real AVFoundation adapters.

/// Identifies a validated local export output.
public struct OutputID: Sendable, Hashable, Codable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum ExportFailure: Error, Sendable, Equatable {
    case unsupportedSource
    case sourceUnavailable
    case insufficientStorage
    case renderFailed
    case writerFailed
    case validationFailed
    case cancelled
}

/// Renders and validates one export into `outputURL` (AVFoundation adapter in the app).
/// Honors task cancellation and removes its partial file on any failure (05 V09).
public protocol ExportRendering: Sendable {
    func render(
        plan: ExportPlan,
        sourceURL: URL,
        outputURL: URL,
        progress: @escaping @Sendable (_ renderedSeconds: Double) -> Void
    ) async throws(ExportFailure) -> RationalTime
}

public enum PhotosSaveOutcome: Sendable, Equatable {
    case saved(localIdentifier: String?)
    case permissionDenied
    case failed
}

/// Add-only Photos saving (05 V09). Never deletes or edits library content.
public protocol PhotosSaving: Sendable {
    func saveVideo(at url: URL) async -> PhotosSaveOutcome
}

public enum MediaPreparationFailure: Error, Sendable, Equatable {
    case unreadable
    case noVideoTrack
    case unsupportedFormat
    case insufficientStorage
    case cancelled
}

/// A picked video copied into app-owned staging and inspected (05 V06). The picker's
/// temporary URL is never persisted.
public struct PreparedImport: Sendable, Equatable {
    public let stagedFile: URL
    public let fileExtension: String
    public let profile: SourceMediaProfile
    /// HDR input converted through the SDR path; disclosed in the export summary (05 V01).
    public let isHDR: Bool

    public init(stagedFile: URL, fileExtension: String, profile: SourceMediaProfile, isHDR: Bool) {
        self.stagedFile = stagedFile
        self.fileExtension = fileExtension
        self.profile = profile
        self.isHDR = isHDR
    }
}

/// Copies a picker file into staging and inspects it (AVFoundation adapter in the app).
public protocol VideoImporting: Sendable {
    func prepare(pickedFile: URL) async throws(MediaPreparationFailure) -> PreparedImport
    /// Removes a staged import that will not become a project (cancel / Free limit declined).
    func discard(_ prepared: PreparedImport) async
}
