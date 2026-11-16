import Foundation
import Testing
@testable import SMNCore

@Suite("Alert groups")
struct AlertGroupTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func a(_ id: String, _ event: String, _ severity: String, hours: Double, shortTerm: Bool = false) -> CAPAlert {
        var x = alert(id, event, severity, shortTerm: shortTerm)
        x.expires = t0.addingTimeInterval(hours * 3600)
        return x
    }

    /// The real case from 2026-11-16: one storm as three files (two identical yellow, one orange later).
    @Test func oneStormSplitByTimeBecomesOneRowWithTimeline() throws {
        let groups = groupAlerts([a("o", "Tormentas", "Severe", hours: 6), a("y1", "Tormentas", "Moderate", hours: 1),
                                  a("y2", "Tormentas", "Moderate", hours: 1)])
        let g = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(g.worst.level == .orange)
        #expect(g.timeline == [.init(level: .yellow, until: t0.addingTimeInterval(3600)),
                               .init(level: .orange, until: t0.addingTimeInterval(6 * 3600))])
    }

    @Test func shortTermNoticesComeFirstThenByLevel() {
        let groups = groupAlerts([a("1", "Viento", "Moderate", hours: 2), a("2", "Tormentas", "Extreme", hours: 5),
                                  a("3", "TORMENTAS FUERTES", "Severe", hours: 1, shortTerm: true)])
        #expect(groups.map(\.worst.id) == ["3", "2", "1"])
    }

    @Test func noticesAndAlertsOfTheSameEventStayApart() {
        let groups = groupAlerts([a("1", "Tormentas", "Moderate", hours: 2), a("2", "TORMENTAS", "Severe", hours: 1, shortTerm: true)])
        #expect(groups.count == 2)
    }

    @Test func hailAnywhereInTheGroupCounts() {
        var withHail = a("2", "Tormentas", "Moderate", hours: 2)
        withHail.description = "ocasional granizo"
        #expect(groupAlerts([a("1", "Tormentas", "Severe", hours: 1), withHail]).first?.mentionsHail == true)
    }
}
