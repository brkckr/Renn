import Foundation
import RENNDomain

/// Loads and validates the Look catalog manifest bundled with the app.
/// The app uses `LookCatalog.json`: the twelve launch Looks (M08), each with a bundled `.cube`
/// named in `scripts/look_lut_sources.json`. `DevelopmentLookCatalog.json` (one labelled
/// diagnostic fixture with `dev_warm.cube`) stays bundled for the rendering tests only.
struct BundledLookCatalogProvider: LookCatalogProviding {
    enum LoadError: Error {
        case missingManifest(String)
    }

    static let defaultManifestName = "LookCatalog"
    static let developmentManifestName = "DevelopmentLookCatalog"

    let manifestName: String

    init(manifestName: String = Self.defaultManifestName) {
        self.manifestName = manifestName
    }

    func catalog() async throws -> LookCatalog {
        try Self.load(bundle: .main, manifestName: manifestName)
    }

    static func load(bundle: Bundle, manifestName: String) throws -> LookCatalog {
        guard let url = bundle.url(forResource: manifestName, withExtension: "json") else {
            throw LoadError.missingManifest(manifestName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LookCatalog.self, from: data)
    }
}
