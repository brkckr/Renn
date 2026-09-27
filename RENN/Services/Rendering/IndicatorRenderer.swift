import CoreImage
import UIKit
import RENNDomain

/// Renders the decorative camcorder indicators (02 D06): readable light glyphs with a dark
/// shadow, static full battery and static REC dot (no live device state, no wall clock).
/// Press Start 2P is used when bundled; until then a monospaced system face stands in
/// (reported in Settings > Developer).
enum IndicatorRenderer {
    struct Overlay {
        let image: CIImage
        let frame: WatermarkLayout.Rect
    }

    /// Images for the placed indicators, drawn once per output size.
    static func overlays(for layout: IndicatorLayout.Result, settings: IndicatorSettings) -> [Overlay] {
        layout.indicators.compactMap { placed in
            render(placed.kind, size: CGSize(width: placed.frame.width, height: placed.frame.height),
                   stamp: settings.stampDate.text)
                .map { Overlay(image: $0, frame: placed.frame) }
        }
    }

    private static func render(_ kind: IndicatorLayout.Kind, size: CGSize, stamp: String) -> CIImage? {
        guard size.width >= 2, size.height >= 2 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: size.height * 0.06), blur: size.height * 0.12,
                         color: UIColor.black.withAlphaComponent(0.7).cgColor)
            let fontSize = size.height * 0.62
            let font = UIFont(name: RENNFont.PostScriptName.pressStart, size: fontSize)
                ?? .monospacedSystemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(white: 0.97, alpha: 1),
            ]
            let textY = (size.height - font.lineHeight) / 2
            switch kind {
            case .rec:
                let dot = size.height * 0.5
                cg.setFillColor(UIColor(red: 0xF1 / 255, green: 0x4A / 255, blue: 0x42 / 255, alpha: 1).cgColor)
                cg.fillEllipse(in: CGRect(x: 0, y: (size.height - dot) / 2, width: dot, height: dot))
                ("REC" as NSString).draw(at: CGPoint(x: dot * 1.4, y: textY), withAttributes: attributes)
            case .play:
                ("PLAY" as NSString).draw(at: CGPoint(x: 0, y: textY), withAttributes: attributes)
                let triangle = size.height * 0.5
                let x = size.width - triangle
                let y = (size.height - triangle) / 2
                cg.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
                cg.move(to: CGPoint(x: x, y: y))
                cg.addLine(to: CGPoint(x: x + triangle, y: y + triangle / 2))
                cg.addLine(to: CGPoint(x: x, y: y + triangle))
                cg.closePath()
                cg.fillPath()
            case .battery:
                let body = CGRect(x: 0, y: size.height * 0.22, width: size.width * 0.86, height: size.height * 0.56)
                cg.setStrokeColor(UIColor(white: 0.97, alpha: 1).cgColor)
                cg.setLineWidth(max(1, size.height * 0.08))
                cg.stroke(body)
                cg.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
                cg.fill(body.insetBy(dx: size.height * 0.12, dy: size.height * 0.12))
                cg.fill(CGRect(x: body.maxX, y: size.height * 0.38, width: size.width * 0.1, height: size.height * 0.24))
            case .date:
                // Frozen YYYY.MM.DD; never localized, never re-read from the clock (01 P07).
                (stamp as NSString).draw(at: CGPoint(x: 0, y: textY), withAttributes: attributes)
            }
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }
}
