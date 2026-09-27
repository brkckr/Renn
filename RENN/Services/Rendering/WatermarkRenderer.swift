import CoreImage
import UIKit
import RENNDomain

/// Renders the exact Free watermark `shot by RENN` (01 P08, 02 D07): "shot by" in Roboto
/// Medium off-white, "RENN" in Monoton with R yellow, E amber, N orange, N red, fine dark
/// shadow, no background card. Fonts fall back to system faces until the licensed files are
/// bundled (reported in Settings > Developer).
enum WatermarkRenderer {
    /// Renders at a height suited to `width` output pixels; returns the image and its aspect.
    static func render(width: Double) -> (image: CIImage, aspectRatio: Double)? {
        let text = attributedText(fontSize: max(8, width / 6))
        let textSize = text.size()
        let padding = textSize.height * 0.15
        let size = CGSize(width: ceil(textSize.width + padding * 2), height: ceil(textSize.height + padding * 2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            text.draw(at: CGPoint(x: padding, y: padding))
        }
        guard let cgImage = rendered.cgImage else { return nil }
        return (CIImage(cgImage: cgImage), Double(size.width / size.height))
    }

    static func attributedText(fontSize: CGFloat) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = max(1, fontSize * 0.08)
        shadow.shadowOffset = CGSize(width: 0, height: max(0.5, fontSize * 0.04))

        let functional = UIFont(name: RENNFont.PostScriptName.robotoMedium, size: fontSize * 0.62)
            ?? .systemFont(ofSize: fontSize * 0.62, weight: .medium)
        let brand = UIFont(name: RENNFont.PostScriptName.monoton, size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .heavy)

        let result = NSMutableAttributedString(string: "shot by ", attributes: [
            .font: functional,
            .foregroundColor: UIColor(white: 0.96, alpha: 1),
            .shadow: shadow,
            .baselineOffset: 0,
        ])
        let colors: [UIColor] = [
            UIColor(red: 0xF8 / 255, green: 0xC4 / 255, blue: 0x3F / 255, alpha: 1),
            UIColor(red: 0xF2 / 255, green: 0xA8 / 255, blue: 0x3A / 255, alpha: 1),
            UIColor(red: 0xF2 / 255, green: 0x7D / 255, blue: 0x3B / 255, alpha: 1),
            UIColor(red: 0xF1 / 255, green: 0x4A / 255, blue: 0x42 / 255, alpha: 1),
        ]
        for (index, glyph) in "RENN".enumerated() {
            result.append(NSAttributedString(string: String(glyph), attributes: [
                .font: brand,
                .foregroundColor: colors[index],
                .shadow: shadow,
            ]))
        }
        return result
    }
}
