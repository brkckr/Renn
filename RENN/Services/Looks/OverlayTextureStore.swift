import CoreImage
import Foundation
import ImageIO
import OSLog

/// Still textures for the film overlays (dust, light leaks, burnt edges), loaded from the app
/// bundle on first use and kept decoded.
///
/// The texture pack's license allows use inside the app but forbids redistributing the files, so
/// they live in the git-ignored `RENN/Resources/Overlays/` folder, installed on the owner's Mac by
/// `scripts/install_overlays.py`. A build without them renders every Look without overlays: a
/// missing texture is logged once and its layer skipped, never a crash.
final class OverlayTextureStore: @unchecked Sendable {
    enum Kind: CaseIterable, Sendable {
        case dust, leakWarm, leakCool, burn

        /// Bundle resource names (`.jpg`), in variant order.
        var resourceNames: [String] {
            switch self {
            case .dust: ["renn_dust_1", "renn_dust_2", "renn_dust_3", "renn_dust_4"]
            case .leakWarm: ["renn_leak_warm"]
            case .leakCool: ["renn_leak_cool"]
            case .burn: ["renn_burn"]
            }
        }
    }

    /// Longest edge after decoding. Enough for 1080p output and a soft look at 4K, while a gray
    /// dust texture stays about 2 MB in memory.
    static let maximumPixelSize = 2048

    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "overlays")

    private let lock = NSLock()
    /// Guarded by `lock`. A kind maps to its loaded variants (possibly empty once tried).
    private var loaded: [Kind: [CIImage]] = [:]
    private let bundle: Bundle?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// For tests: fixed textures, nothing is read from a bundle.
    init(preloaded: [Kind: [CIImage]]) {
        bundle = nil
        loaded = preloaded
    }

    /// Variant `index` (modulo the available count) of a kind, or nil if none is installed.
    func texture(_ kind: Kind, variant index: Int = 0) -> CIImage? {
        let variants = self.variants(kind)
        guard !variants.isEmpty else { return nil }
        return variants[((index % variants.count) + variants.count) % variants.count]
    }

    private func variants(_ kind: Kind) -> [CIImage] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = loaded[kind] { return cached }
        let images = bundle.map { bundle in kind.resourceNames.compactMap { Self.load($0, from: bundle) } } ?? []
        if images.isEmpty {
            Self.logger.notice("No overlay textures installed for \(String(describing: kind), privacy: .public)")
        }
        loaded[kind] = images
        return images
    }

    private static func load(_ name: String, from bundle: Bundle) -> CIImage? {
        guard let url = bundle.url(forResource: name, withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            logger.error("Unreadable overlay texture \(name, privacy: .public)")
            return nil
        }
        return CIImage(cgImage: image)
    }
}
