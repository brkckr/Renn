import Foundation

/// Pose of the travelling case during the VHS insertion motion (03 M05), as a pure function of
/// elapsed time and measured geometry (points, top-left origin). One normalized timeline:
/// lifting 0–150 ms, travelling 150–500 ms along a quadratic curve, inserting 500–700 ms behind
/// the player's front plate, then the preview is presented once.
public enum CassetteInsertion {
    public static let liftEnd = 0.150
    public static let travelEnd = 0.500
    public static let totalDuration = 0.700
    public static let liftDistance = 8.0
    public static let liftScale = 1.05
    public static let peakRotation = -8.0

    public enum Phase: Sendable, Equatable {
        case lifting, travelling, inserting, presenting
    }

    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Geometry: Sendable, Equatable {
        /// Centre and size of the source case in the shared coordinate space.
        public var source: Point
        public var sourceWidth: Double
        public var sourceHeight: Double
        /// Centre of the slot opening (the front plate's lower edge) and its usable width.
        public var slot: Point
        public var slotWidth: Double
        /// Visible bounds used to clamp the curve's control point.
        public var visibleMinY: Double
        public var viewportHeight: Double

        public init(
            source: Point, sourceWidth: Double, sourceHeight: Double,
            slot: Point, slotWidth: Double, visibleMinY: Double, viewportHeight: Double
        ) {
            self.source = source
            self.sourceWidth = sourceWidth
            self.sourceHeight = sourceHeight
            self.slot = slot
            self.slotWidth = slotWidth
            self.visibleMinY = visibleMinY
            self.viewportHeight = viewportHeight
        }
    }

    public struct Pose: Sendable, Equatable {
        public let center: Point
        public let scale: Double
        public let rotationDegrees: Double
        public let shadowOpacity: Double
        public let phase: Phase
    }

    /// Scale at which the case fits the slot entrance.
    public static func slotScale(_ geometry: Geometry) -> Double {
        min(liftScale, geometry.slotWidth / max(1, geometry.sourceWidth))
    }

    /// Travel endpoint: the scaled case sits just below the slot line, ready to slide in.
    public static func entrance(_ geometry: Geometry) -> Point {
        Point(x: geometry.slot.x, y: geometry.slot.y + geometry.sourceHeight * slotScale(geometry) / 2)
    }

    /// Quadratic control point above the midpoint by min(80 pt, 0.12 H), clamped to visible bounds.
    public static func control(_ geometry: Geometry) -> Point {
        let start = Point(x: geometry.source.x, y: geometry.source.y - liftDistance)
        let end = entrance(geometry)
        let rise = min(80, 0.12 * geometry.viewportHeight)
        let y = max(geometry.visibleMinY, min(start.y, end.y) - rise)
        return Point(x: (start.x + end.x) / 2, y: y)
    }

    public static func pose(at elapsed: Double, geometry: Geometry) -> Pose {
        let t = max(0, elapsed)
        let lifted = Point(x: geometry.source.x, y: geometry.source.y - liftDistance)
        if t < liftEnd {
            let p = Easing.standard(t / liftEnd)
            return Pose(
                center: Point(x: geometry.source.x, y: geometry.source.y - liftDistance * p),
                scale: 1 + (liftScale - 1) * p, rotationDegrees: 0, shadowOpacity: 0.25 + 0.2 * p, phase: .lifting)
        }
        let end = entrance(geometry)
        let targetScale = slotScale(geometry)
        if t < travelEnd {
            let raw = (t - liftEnd) / (travelEnd - liftEnd)
            let p = Easing.standard(raw)
            let c = control(geometry)
            let u = 1 - p
            let x = u * u * lifted.x + 2 * u * p * c.x + p * p * end.x
            let y = u * u * lifted.y + 2 * u * p * c.y + p * p * end.y
            // 0° → −8° → 0°, peaking at the middle of the travel time.
            let rotation = peakRotation * sin(Double.pi * raw)
            return Pose(
                center: Point(x: x, y: y), scale: liftScale + (targetScale - liftScale) * p,
                rotationDegrees: rotation, shadowOpacity: 0.45, phase: .travelling)
        }
        if t < totalDuration {
            let p = Easing.standard((t - travelEnd) / (totalDuration - travelEnd))
            // Slides up by its own scaled height: fully behind the front plate at the end.
            let height = geometry.sourceHeight * targetScale
            return Pose(
                center: Point(x: end.x, y: end.y - height * p), scale: targetScale,
                rotationDegrees: 0, shadowOpacity: 0.45 * (1 - p), phase: .inserting)
        }
        let height = geometry.sourceHeight * targetScale
        return Pose(
            center: Point(x: end.x, y: end.y - height), scale: targetScale,
            rotationDegrees: 0, shadowOpacity: 0, phase: .presenting)
    }
}
