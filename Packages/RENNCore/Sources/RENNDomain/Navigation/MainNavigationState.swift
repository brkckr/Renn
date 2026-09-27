/// Main tabs, in the settled order (01 P02).
public enum AppTab: Int, Sendable, CaseIterable, Hashable {
    case home
    case looks
    case projects
    case settings
}

/// The three rows of the Home creation menu (01 P02, 02 D04).
public enum CreationAction: Sendable, CaseIterable, Hashable {
    case recordVideo
    case recordWithBothCameras
    case importVideo
}

/// One confirmed creation choice, captured once, with the optional Look chosen via
/// "Create with this Look" in the catalog (02 D05).
public struct CreationRequest: Sendable, Equatable {
    public let action: CreationAction
    public let lookID: LookID?

    public init(action: CreationAction, lookID: LookID?) {
        self.action = action
        self.lookID = lookID
    }
}

/// Pure navigation rules for the main tab shell. The app router wraps this value;
/// motion timing lives in the views (03 M03).
public struct MainNavigationState: Sendable, Equatable {
    public private(set) var selectedTab: AppTab = .home
    public private(set) var isCreationMenuOpen = false
    /// Temporary Look intent from the catalog; cleared when the menu is dismissed.
    public private(set) var pendingLookID: LookID?

    public init() {}

    /// The + exists only on Home and is absent from hit-testing elsewhere.
    public var isCreateButtonAvailable: Bool { selectedTab == .home }

    /// Selecting a tab closes an open menu without creating anything.
    public mutating func select(_ tab: AppTab) {
        if isCreationMenuOpen { dismissCreationMenu() }
        selectedTab = tab
    }

    /// Opens the menu. Only valid on Home; returns whether the menu is now open.
    @discardableResult
    public mutating func openCreationMenu() -> Bool {
        guard selectedTab == .home else { return false }
        isCreationMenuOpen = true
        return true
    }

    /// Catalog "Create with this Look": return Home with a temporary Look and open the menu.
    public mutating func startCreation(withLook lookID: LookID) {
        selectedTab = .home
        pendingLookID = lookID
        isCreationMenuOpen = true
    }

    /// Outside tap, × or accessible dismiss: closes and clears the pending Look intent.
    public mutating func dismissCreationMenu() {
        isCreationMenuOpen = false
        pendingLookID = nil
    }

    /// Captures a chosen action exactly once. A repeated tap after the menu closed returns nil.
    public mutating func choose(_ action: CreationAction) -> CreationRequest? {
        guard isCreationMenuOpen else { return nil }
        let request = CreationRequest(action: action, lookID: pendingLookID)
        isCreationMenuOpen = false
        pendingLookID = nil
        return request
    }
}
