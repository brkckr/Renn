import Foundation
import Observation
import RENNDomain

/// A staged Look choice in a Look selector (02 D05): applied as one change, or discarded.
public struct LookSelection: Equatable, Sendable {
    public var lookID: LookID?
    public var intensity: Double

    public init(lookID: LookID?, intensity: Double) {
        self.lookID = lookID
        self.intensity = intensity
    }

    /// The recipe with this selection: another Look loads its snapshot/defaults first, then the
    /// staged intensity applies. Unknown Look IDs leave the Look unchanged.
    public func applied(to recipe: Recipe, catalog: LookCatalog?) -> Recipe {
        var result = recipe
        if lookID != recipe.lookID, let id = lookID, let look = catalog?.look(id) {
            result = recipe.switchingLook(to: look)
        }
        if let value = LookIntensity(intensity) { result.intensity = value }
        return result
    }

    /// Selecting another Look stages its default intensity; the recipe's own Look restores the
    /// saved intensity. Nil when the ID is not in the catalog.
    public static func staging(_ id: LookID, over recipe: Recipe, catalog: LookCatalog?) -> LookSelection? {
        if id == recipe.lookID { return LookSelection(lookID: id, intensity: recipe.intensity.value) }
        guard let look = catalog?.look(id) else { return nil }
        return LookSelection(lookID: id, intensity: look.defaultIntensity.value)
    }
}

/// The camera's pre-record recipe (02 D06): Look (staged selector), Beat and indicators chosen
/// before recording seed the new project. Every change is refused while `isLocked` (recording,
/// countdown, finalizing), so the take is recorded with one fixed recipe.
@MainActor
@Observable
public final class RecipeDraftEditor {
    public private(set) var recipe: Recipe?
    public private(set) var catalog: LookCatalog?
    public private(set) var lookSelection: LookSelection?
    public var isLocked = false

    public init() {}

    func begin(_ recipe: Recipe, catalog: LookCatalog?) {
        self.recipe = recipe
        self.catalog = catalog
    }

    /// The staged Look while the selector is open, else the draft.
    public var displayRecipe: Recipe? {
        guard let recipe else { return nil }
        return lookSelection.map { $0.applied(to: recipe, catalog: catalog) } ?? recipe
    }

    public func openLookSelector() {
        guard !isLocked, let recipe, lookSelection == nil else { return }
        lookSelection = LookSelection(lookID: recipe.lookID, intensity: recipe.intensity.value)
    }

    public func stageLook(_ id: LookID) {
        guard lookSelection != nil, let recipe,
              let staged = LookSelection.staging(id, over: recipe, catalog: catalog)
        else { return }
        lookSelection = staged
    }

    public func stageIntensity(_ value: Double) {
        guard lookSelection != nil, LookIntensity(value) != nil else { return }
        lookSelection?.intensity = value
    }

    public func applyLookSelection() {
        guard let selection = lookSelection, let recipe else { return }
        lookSelection = nil
        guard !isLocked else { return }
        self.recipe = selection.applied(to: recipe, catalog: catalog)
    }

    public func cancelLookSelection() {
        lookSelection = nil
    }

    public func setBeatEnabled(_ enabled: Bool) {
        guard !isLocked, var recipe else { return }
        recipe.beat = BeatSettings(isEnabled: enabled, intensity: recipe.beat.intensity)
        self.recipe = recipe
    }

    public func setBeatIntensity(_ value: Double) {
        guard !isLocked, var recipe else { return }
        recipe.beat = BeatSettings(isEnabled: recipe.beat.isEnabled, intensity: value)
        self.recipe = recipe
    }

    public func applyIndicators(_ draft: IndicatorsDraft) {
        guard !isLocked, var recipe else { return }
        recipe.indicators = draft.applied(to: recipe.indicators)
        self.recipe = recipe
    }
}
