import SwiftUI

@main
struct RENNApp: App {
    @State private var composition: AppComposition

    init() {
        FontRegistry.registerBundledFonts()
        _composition = State(initialValue: AppComposition.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView(composition: composition)
        }
    }
}
