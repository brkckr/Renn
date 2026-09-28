import Foundation
import RENNDomain

/// Polls a main-actor condition until true or a bounded timeout, for stream-driven
/// ViewModel updates. Fails the expectation at the call site if it never becomes true.
/// The budget is generous because all main-actor tests share one executor: on a loaded CI
/// runner an observation task may wait seconds for its turn. A passing condition returns
/// immediately, so the budget only matters for real failures.
@MainActor
func eventually(timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

func makeProject(_ name: String, minutesAgo: Double) -> ProjectSummary {
    let date = Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60)
    return ProjectSummary(
        id: ProjectID(), name: try! ProjectName(name), createdAt: date, updatedAt: date,
        sourceMode: .camera, readiness: .ready, lookID: nil)
}

func makeLook(_ id: String, family: String = "vhs") -> LookDefinition {
    LookDefinition(
        id: LookID(id), version: 1, family: family, nameKey: "look.\(id).name",
        descriptionKey: "look.\(id).description", defaultIntensity: LookIntensity(0.5)!,
        renderVersion: 1, isDevelopmentFixture: false)
}

/// Main-actor call log for navigation closures.
@MainActor
final class CallLog {
    var entries: [String] = []
    func record(_ entry: String) { entries.append(entry) }
}
