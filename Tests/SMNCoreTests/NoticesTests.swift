import Foundation
import Testing
@testable import SMNCore

@Suite("Notices")
struct NoticesTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let cba = City(name: "Córdoba, Córdoba", coordinate: Coordinate(lat: -31.4, lon: -64.2))

    func a(_ id: String, _ severity: String, hours: Double, event: String = "Tormentas") -> CAPAlert {
        var x = alert(id, event, severity)
        x.expires = t0.addingTimeInterval(hours * 3600)
        return x
    }

    /// The real SMN shape: yellow until +h, then orange.
    func storm(yellowFor h: Double) -> [CAPAlert] { [a("y", "Moderate", hours: h), a("o", "Severe", hours: h + 6)] }

    @Test func escalationWithinTheHourIsAnnouncedOnce() {
        let place = Place(city: rc, alerts: storm(yellowFor: 0.75))
        let known = NoticeState(levels: ["\(rc.name)|TORMENTAS": .orange])
        let (first, state) = planNotices(places: [place], previous: known, now: t0, partial: false)
        #expect(first == [.escalation(event: "Tormentas", to: .orange, at: t0.addingTimeInterval(0.75 * 3600), city: rc)])
        let (second, _) = planNotices(places: [place], previous: state, now: t0.addingTimeInterval(300), partial: false)
        #expect(second.isEmpty)
    }

    @Test func noEscalationWhenTheChangeIsMoreThanAnHourAway() {
        let known = NoticeState(levels: ["\(rc.name)|TORMENTAS": .orange])
        let (notices, state) = planNotices(places: [Place(city: rc, alerts: storm(yellowFor: 3))], previous: known,
                                           now: t0, partial: false)
        #expect(notices.isEmpty)
        #expect(state.escalations.isEmpty)       // still owed: it fires when the hour comes
    }

    @Test func arrivalInsideTheHourDoesNotAlsoSendAnEscalation() {
        let (notices, _) = planNotices(places: [Place(city: rc, alerts: storm(yellowFor: 0.5))], previous: .init(),
                                       now: t0, partial: false)
        #expect(notices.map(\.level) == [.orange])
        #expect(notices.first?.alert != nil)
    }

    @Test func endedOnceTheAlertIsGone() {
        let known = NoticeState(levels: ["\(rc.name)|TORMENTAS": .orange, "\(rc.name)|ACP:TORMENTAS FUERTES": .red])
        let (notices, state) = planNotices(places: [Place(city: rc, alerts: [])], previous: known, now: t0, partial: false)
        #expect(Set(notices.map { "\($0)" }) == Set([Notice.ended(event: "Tormentas", level: .orange, city: rc),
                                                      .ended(event: "Tormentas fuertes", level: .red, city: rc)].map { "\($0)" }))
        #expect(state.levels.isEmpty)
    }

    @Test func nothingEndsWhileZonesArePending() {
        let known = NoticeState(levels: ["\(rc.name)|TORMENTAS": .orange])
        let (notices, state) = planNotices(places: [Place(city: rc, alerts: [])], previous: known, now: t0, partial: true)
        #expect(notices.isEmpty)
        #expect(state == known)
    }

    @Test func eachCityIsTrackedOnItsOwn() {
        let storm = [a("1", "Severe", hours: 5)]
        let (first, state) = planNotices(places: [Place(city: rc, alerts: storm), Place(city: cba, alerts: [])],
                                         previous: .init(), now: t0, partial: false)
        #expect(first == [.new(storm[0], city: rc)])
        // The storm moves: Córdoba gets it too (new there), Río Cuarto already knew.
        let (second, _) = planNotices(places: [Place(city: rc, alerts: storm), Place(city: cba, alerts: storm)],
                                      previous: state, now: t0, partial: false)
        #expect(second == [.new(storm[0], city: cba)])
    }

    @Test func removedCitiesNeverReportEnded() {
        let known = NoticeState(levels: ["\(cba.name)|TORMENTAS": .yellow])
        let (notices, _) = planNotices(places: [Place(city: rc, alerts: [])], previous: known, now: t0, partial: false)
        #expect(notices.isEmpty)
    }
}

@Suite("AlarmPolicy minimum level")
struct MinimumLevelTests {
    @Test func announcesOnlyFromTheChosenLevel() {
        var p = AlarmPolicy()
        #expect(AlertLevel.allCases.allSatisfy(p.announces))
        p.minimumLevel = .orange
        #expect(AlertLevel.allCases.filter(p.announces) == [.orange, .red])
    }
}
