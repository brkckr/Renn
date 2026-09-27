import Foundation
import RENNDomain

/// Loads and validates the Look catalog manifest bundled with the app.
/// M00 ships only `DevelopmentLookCatalog.json`: one labelled diagnostic fixture. The
/// reviewed twelve-Look manifest replaces it in M08 when the owner's assets arrive.
struct BundledLookCatalogProvider: LookCatalogProviding {
    enum LoadError: Error {
        case missingManifest(String)
    }

    let manifestName: String

    init(manifestName: String = "DevelopmentLookCatalog") {
        self.manifestName = manifestName
    }

    func catalog() async throws -> LookCatalog {
        guard let url = Bundle.main.url(forResource: manifestName, withExtension: "json") else {
            throw LoadError.missingManifest(manifestName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LookCatalog.self, from: data)
    }
}
