import Foundation
import OSLog
import RENNDomain

/// Resolves a Look's bundled `.cube` LUT into `CIColorCubeWithColorSpace` data (05 V04).
///
/// Loaded lazily on first use from the same bundled manifest as `BundledLookCatalogProvider`,
/// then immutable. A LUT that is missing or invalid is logged and skipped: the Look still
/// renders its parameter stages, never a crash or a half-built cube.
final class LookLUTStore: @unchecked Sendable {
    struct Prepared: Sendable {
        let dimension: Int
        /// RGBA Float32 entries, red varying fastest.
        let data: Data
    }

    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "looks")

    private enum Source {
        case bundled(Bundle, manifestName: String)
        case fixed([LookID: Prepared])
    }

    private let lock = NSLock()
    /// Guarded by `lock`; `source` is immutable.
    private var table: [LookID: Prepared]?
    private let source: Source

    init(bundle: Bundle = .main, manifestName: String = BundledLookCatalogProvider.defaultManifestName) {
        source = .bundled(bundle, manifestName: manifestName)
    }

    /// For tests: a fixed table.
    init(preloaded: [LookID: Prepared]) {
        source = .fixed(preloaded)
    }

    func lut(for id: LookID) -> Prepared? {
        lock.lock()
        defer { lock.unlock() }
        if table == nil {
            switch source {
            case let .bundled(bundle, manifestName): table = Self.loadBundled(bundle: bundle, manifestName: manifestName)
            case let .fixed(fixed): table = fixed
            }
        }
        return table?[id]
    }

    static func prepare(_ lut: CubeLUT) -> Prepared? {
        // CIColorCube samples a 0...1 cube; other domains are not supported by render version 1.
        guard lut.domainMin == [0, 0, 0], lut.domainMax == [1, 1, 1] else { return nil }
        let floats = lut.rgbaFloats
        return Prepared(dimension: lut.size, data: floats.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    private static func loadBundled(bundle: Bundle, manifestName: String) -> [LookID: Prepared] {
        let catalog: LookCatalog
        do {
            catalog = try BundledLookCatalogProvider.load(bundle: bundle, manifestName: manifestName)
        } catch {
            logger.error("Look catalog unavailable for LUTs: \(String(describing: error), privacy: .public)")
            return [:]
        }
        var result: [LookID: Prepared] = [:]
        for look in catalog.looks {
            guard let name = look.lut else { continue }
            guard let url = bundle.url(forResource: name, withExtension: "cube"),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else {
                logger.error("Missing LUT \(name, privacy: .public) for \(look.id.rawValue, privacy: .public)")
                continue
            }
            do {
                guard let prepared = prepare(try CubeLUT.parse(text)) else {
                    logger.error("Unsupported LUT domain in \(name, privacy: .public)")
                    continue
                }
                result[look.id] = prepared
            } catch {
                logger.error("Invalid LUT \(name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        return result
    }
}
