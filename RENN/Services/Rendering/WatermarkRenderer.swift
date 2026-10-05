import CoreImage
import UIKit
import RENNDomain

/// Renders the exact Free watermark `shot by RENN` (01 P08, 02 D07). Owner-approved design
/// (2026-10-05): a film-credit line "— SHOT BY —" in letter-spaced Roboto Medium caps, off-white
/// with a fixed red/cyan VHS channel split, centered over "RENN" in Monoton with R yellow,
/// E amber, N orange, N red and a fine dark shadow. RENN itself stays clean; nothing animates,
/// no gradient, stripes or card. Fonts fall back to system faces until the licensed files are
/// bundled (reported in Settings > Developer).
enum WatermarkRenderer {
    /// Proportions as fractions of the RENN font size, from the approved mockup.
    private enum Metric {
        static let creditSize: CGFloat = 0.2
        static let creditKern: CGFloat = 0.093
        static let ruleLength: CGFloat = 1.0 / 3.0
        static let ruleThickness: CGFloat = 0.02
        static let ruleGap: CGFloat = 0.093
        /// Credit cap bottom to RENN cap top.
        static let lineGap: CGFloat = 0.18
        /// Red copy left, cyan copy right, by this much.
        static let split: CGFloat = 0.0233
        /// Room around the glyphs for the split and the shadow.
        static let padding: CGFloat = 0.12
    }

    private static var off: UIColor { UIColor(white: 0.96, alpha: 1) }
    private static var splitRed: UIColor { UIColor(red: 0xF1 / 255, green: 0x4A / 255, blue: 0x42 / 255, alpha: 0.9) }
    private static var splitCyan: UIColor { UIColor(red: 80 / 255, green: 200 / 255, blue: 1, alpha: 0.8) }
    private static var brandColors: [UIColor] {
        [
            UIColor(red: 0xF8 / 255, green: 0xC4 / 255, blue: 0x3F / 255, alpha: 1),
            UIColor(red: 0xF2 / 255, green: 0xA8 / 255, blue: 0x3A / 255, alpha: 1),
            UIColor(red: 0xF2 / 255, green: 0x7D / 255, blue: 0x3B / 255, alpha: 1),
            UIColor(red: 0xF1 / 255, green: 0x4A / 255, blue: 0x42 / 255, alpha: 1),
        ]
    }

    /// Renders about `width` output pixels wide; returns the image and its aspect (width / height).
    static func render(width: Double) -> (image: CIImage, aspectRatio: Double)? {
        guard width > 0 else { return nil }
        // Size the RENN font so the whole mark lands near the requested width (crisp, not rescaled much).
        let reference = Layout(fontSize: 100)
        let layout = Layout(fontSize: max(8, 100 * CGFloat(width) / reference.size.width))
        let size = CGSize(width: ceil(layout.size.width), height: ceil(layout.size.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            layout.draw(in: context.cgContext, canvasWidth: size.width)
        }
        guard let cgImage = rendered.cgImage else { return nil }
        return (CIImage(cgImage: cgImage), Double(size.width / size.height))
    }

    /// Measured geometry for one RENN font size.
    private struct Layout {
        static let credit = "SHOT BY"

        let fontSize: CGFloat
        let creditFont: UIFont
        let brandFont: UIFont
        let creditSize: CGSize
        let rennSize: CGSize
        let size: CGSize

        init(fontSize: CGFloat) {
            self.fontSize = fontSize
            creditFont = UIFont(name: RENNFont.PostScriptName.robotoMedium, size: fontSize * Metric.creditSize)
                ?? .systemFont(ofSize: fontSize * Metric.creditSize, weight: .medium)
            brandFont = UIFont(name: RENNFont.PostScriptName.monoton, size: fontSize)
                ?? .systemFont(ofSize: fontSize, weight: .heavy)
            creditSize = Self.creditString(Self.credit, font: creditFont, fontSize: fontSize, color: WatermarkRenderer.off).size()
            rennSize = Self.rennString(font: brandFont, shadow: nil).size()
            let creditLine = creditSize.width + 2 * (fontSize * (Metric.ruleLength + Metric.ruleGap))
            let padding = fontSize * Metric.padding
            let height = creditFont.capHeight + fontSize * Metric.lineGap + brandFont.capHeight
            size = CGSize(width: max(creditLine, rennSize.width) + padding * 2, height: height + padding * 2)
        }

        func draw(in context: CGContext, canvasWidth: CGFloat) {
            let padding = fontSize * Metric.padding
            let shadowColor = UIColor.black.withAlphaComponent(0.55)
            let shadow = NSShadow()
            shadow.shadowColor = shadowColor
            shadow.shadowBlurRadius = max(1, fontSize * 0.08)
            shadow.shadowOffset = CGSize(width: 0, height: max(0.5, fontSize * 0.04))

            // Credit line: baseline sits one cap height below the padding.
            let creditBaseline = padding + creditFont.capHeight
            let creditX = (canvasWidth - creditSize.width) / 2
            let ruleLength = fontSize * Metric.ruleLength
            let ruleGap = fontSize * Metric.ruleGap
            let ruleHeight = max(1, fontSize * Metric.ruleThickness)
            let ruleY = creditBaseline - creditFont.capHeight / 2 - ruleHeight / 2
            let rules = [
                CGRect(x: creditX - ruleGap - ruleLength, y: ruleY, width: ruleLength, height: ruleHeight),
                CGRect(x: creditX + creditSize.width + ruleGap, y: ruleY, width: ruleLength, height: ruleHeight),
            ]
            let split = max(0.75, fontSize * Metric.split)
            // VHS split: red copy left and cyan copy right (with the dark shadow), off-white on top.
            let passes: [(dx: CGFloat, color: UIColor, shadowed: Bool)] = [
                (-split, WatermarkRenderer.splitRed, true),
                (split, WatermarkRenderer.splitCyan, true),
                (0, WatermarkRenderer.off, false),
            ]
            for (dx, color, withShadow) in passes {
                context.saveGState()
                if withShadow {
                    context.setShadow(offset: shadow.shadowOffset, blur: shadow.shadowBlurRadius, color: shadowColor.cgColor)
                }
                context.setFillColor(color.cgColor)
                for rule in rules { context.fill(rule.offsetBy(dx: dx, dy: 0)) }
                Self.creditString(Self.credit, font: creditFont, fontSize: fontSize, color: color)
                    .draw(at: CGPoint(x: creditX + dx, y: creditBaseline - creditFont.ascender))
                context.restoreGState()
            }

            // RENN: clean brand glyphs with the fine dark shadow, centered under the credit.
            let rennBaseline = creditBaseline + fontSize * Metric.lineGap + brandFont.capHeight
            Self.rennString(font: brandFont, shadow: shadow)
                .draw(at: CGPoint(x: (canvasWidth - rennSize.width) / 2, y: rennBaseline - brandFont.ascender))
        }

        /// Letter-spaced caps; the last letter carries no trailing space so the line centers.
        static func creditString(_ text: String, font: UIFont, fontSize: CGFloat, color: UIColor) -> NSAttributedString {
            let result = NSMutableAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: fontSize * Metric.creditKern,
            ])
            result.removeAttribute(.kern, range: NSRange(location: result.length - 1, length: 1))
            return result
        }

        static func rennString(font: UIFont, shadow: NSShadow?) -> NSAttributedString {
            let result = NSMutableAttributedString()
            for (index, glyph) in "RENN".enumerated() {
                var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: WatermarkRenderer.brandColors[index]]
                if let shadow { attributes[.shadow] = shadow }
                result.append(NSAttributedString(string: String(glyph), attributes: attributes))
            }
            return result
        }
    }
}
