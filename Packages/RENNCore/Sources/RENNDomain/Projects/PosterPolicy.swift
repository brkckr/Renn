import Foundation

/// Poster (case print) rules (01 P03, 05 V07): the project's own processed frame at a
/// deterministic representative time; cached by project, recipe revision and render version.
/// Failures never substitute an unrelated image.
public enum PosterPolicy {
    /// Near one second, or the midpoint for clips shorter than two seconds.
    public static func representativeTime(duration: RationalTime) -> RationalTime {
        if duration >= .seconds(2) { return .seconds(1) }
        return (try? RationalTime(value: duration.value, timescale: duration.timescale.multipliedReportingOverflow(by: 2).overflow
            ? duration.timescale : duration.timescale * 2)) ?? .zero
    }

    public static func cacheKey(project: ProjectID, recipeRevision: Int, renderVersion: Int) -> String {
        "poster-\(project.rawValue.uuidString)-r\(recipeRevision)-v\(renderVersion)"
    }
}

/// Supplies the processed-frame poster of a project as JPEG data (app adapter renders it with
/// the shared RenderEngine). Nil while unavailable: callers show an empty case shell.
public protocol PosterProviding: Sendable {
    func posterJPEG(for project: ProjectID) async -> Data?
}
