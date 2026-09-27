/// Product gate evaluated after inspecting a picked video and before a project exists
/// (01 P08, 05 V06). Free sources over 30 seconds offer Pro or another source; there is
/// no automatic trim and no trim editor.
public enum ImportDecision: Sendable, Equatable {
    case accept(OutputPolicy)
    case requiresProForDuration(limit: RationalTime, sourceDuration: RationalTime)
}

public enum ImportGate {
    public static func evaluate(_ profile: SourceMediaProfile, access: AccessState) -> ImportDecision {
        switch AccessPolicy.resolve(source: profile, tier: access.effectiveTier) {
        case .allowed(let policy):
            return .accept(policy)
        case .exceedsFreeDuration(let limit, let duration):
            return .requiresProForDuration(limit: limit, sourceDuration: duration)
        }
    }
}
