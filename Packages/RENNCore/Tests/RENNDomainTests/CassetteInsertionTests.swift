import Foundation
import Testing
@testable import RENNDomain

@Suite("VHS insertion motion (03 M05)")
struct CassetteInsertionTests {
    typealias P = CassetteInsertion.Point
    let geometry = CassetteInsertion.Geometry(
        source: P(x: 300, y: 600), sourceWidth: 100, sourceHeight: 150,
        slot: P(x: 200, y: 180), slotWidth: 80, visibleMinY: 60, viewportHeight: 800)

    @Test func liftsThenTravelsThenInsertsThenPresents() {
        let start = CassetteInsertion.pose(at: 0, geometry: geometry)
        #expect(start.center == P(x: 300, y: 600) && start.scale == 1 && start.phase == .lifting)

        let lifted = CassetteInsertion.pose(at: 0.149_999, geometry: geometry)
        #expect(abs(lifted.center.y - 592) < 0.01 && abs(lifted.scale - 1.05) < 0.001)

        let midTravel = CassetteInsertion.pose(at: 0.325, geometry: geometry)
        #expect(midTravel.phase == .travelling)
        #expect(midTravel.rotationDegrees < -7.9, "Peak −8° mid-travel (\(midTravel.rotationDegrees))")

        let entrance = CassetteInsertion.entrance(geometry)
        let atSlot = CassetteInsertion.pose(at: 0.5, geometry: geometry)
        #expect(atSlot.phase == .inserting)
        #expect(abs(atSlot.center.x - entrance.x) < 0.001 && abs(atSlot.center.y - entrance.y) < 0.001)
        #expect(atSlot.rotationDegrees == 0)

        let done = CassetteInsertion.pose(at: 0.7, geometry: geometry)
        #expect(done.phase == .presenting && done.shadowOpacity == 0)
        let scaledHeight = 150 * CassetteInsertion.slotScale(geometry)
        #expect(abs((done.center.y + scaledHeight / 2) - geometry.slot.y) < 0.001,
                "Bottom edge reaches the slot line: fully behind the front plate")
    }

    @Test func slotScaleFitsTheEntranceAndNeverGrowsBeyondTheLift() {
        #expect(CassetteInsertion.slotScale(geometry) == 0.8)
        var wide = geometry
        wide.slotWidth = 400
        #expect(CassetteInsertion.slotScale(wide) == 1.05)
    }

    @Test func controlPointRisesAboveTheMidpointAndStaysVisible() {
        let control = CassetteInsertion.control(geometry)
        let entrance = CassetteInsertion.entrance(geometry)
        #expect(control.x == (300 + entrance.x) / 2)
        #expect(abs(control.y - (entrance.y - 80)) < 0.001, "min(80, 0.12 × 800) above the higher endpoint")
        var tight = geometry
        tight.visibleMinY = 250
        #expect(CassetteInsertion.control(tight).y == 250, "Clamped to visible bounds")
    }

    @Test func travelIsContinuousAcrossPhaseBoundaries() {
        for boundary in [CassetteInsertion.liftEnd, CassetteInsertion.travelEnd, CassetteInsertion.totalDuration] {
            let before = CassetteInsertion.pose(at: boundary - 1e-6, geometry: geometry)
            let after = CassetteInsertion.pose(at: boundary, geometry: geometry)
            #expect(abs(before.center.x - after.center.x) < 0.01 && abs(before.center.y - after.center.y) < 0.01)
            #expect(abs(before.scale - after.scale) < 0.001)
        }
    }
}
