import Testing
import Foundation
@testable import SleepDaddy

struct VitalsColorZoneTests {
    @Test func boundariesAreInclusiveAtTheirLowerEdge() {
        #expect(VitalsColorZone.zone(forSpO2: 91) == .normal)
        #expect(VitalsColorZone.zone(forSpO2: 90) == .normal)
        #expect(VitalsColorZone.zone(forSpO2: 89) == .warning)
        #expect(VitalsColorZone.zone(forSpO2: 86) == .warning)
        #expect(VitalsColorZone.zone(forSpO2: 85) == .warning)
        #expect(VitalsColorZone.zone(forSpO2: 84) == .critical)
    }

    @Test func extremesLandInTheExpectedZones() {
        #expect(VitalsColorZone.zone(forSpO2: 100) == .normal)
        #expect(VitalsColorZone.zone(forSpO2: 73) == .critical)
        #expect(VitalsColorZone.zone(forSpO2: 0) == .critical)
    }

    @Test func legendLabelsStateNumbersRatherThanVerdicts() {
        // The threshold is a display choice; a word like "Critical" would be a verdict,
        // and the app does not characterise what it draws.
        #expect(VitalsColorZone.normal.legendLabel == "90% and above")
        #expect(VitalsColorZone.warning.legendLabel == "85–90%")
        #expect(VitalsColorZone.critical.legendLabel == "Below 85%")

        for zone in VitalsColorZone.allCases {
            let label = zone.legendLabel.lowercased()
            for verdict in ["critical", "danger", "severe", "concerning", "normal", "bad", "good"] {
                #expect(!label.contains(verdict), "\(zone) label leaks a verdict: \(zone.legendLabel)")
            }
        }
    }

    @Test func zonesDescendInValueOrder() {
        #expect(VitalsColorZone.allCases == [.normal, .warning, .critical])
    }

    @Test func eachZoneHasADistinctUpperBound() {
        #expect(VitalsColorZone.warningLowerBound == 85)
        #expect(VitalsColorZone.normalLowerBound == 90)
    }

    @Test func zoneRangesTileTheScaleWithoutOverlapOrGap() {
        for value in UInt8(0)...UInt8(100) {
            let matching = VitalsColorZone.allCases.filter { $0.contains(spo2: value) }
            #expect(matching.count == 1, "value \(value) matched \(matching.count) zones")
            #expect(matching[0] == VitalsColorZone.zone(forSpO2: value))
        }
    }
}
