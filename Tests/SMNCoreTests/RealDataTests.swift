import Foundation
import Testing
@testable import SMNCore

/// Real files published by the SMN on 2026-11-16, so a format change on their side breaks a test.
@Suite("Real SMN files")
struct RealDataTests {
    func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func alertFromAlertsSystem() throws {
        let url = URL(string: "https://ssl.smn.gob.ar/feeds/CAP/xml_generados/CAP_20261116205447_Tormenta_Llanura_alertas_alertas_1.xml")!
        let a = try #require(CAPParser.parse(try fixture("alerta"), url: url))
        #expect(a.event == "Tormentas")
        #expect(a.level == .orange)
        #expect(!a.isShortTerm)
        #expect(a.symbolName == "cloud.bolt.rain")
        #expect(a.expires == ISO8601DateFormatter().date(from: "2026-11-17T02:59:59-03:00"))
        #expect(!a.instruction.isEmpty)
        #expect(a.contains(Coordinate(lat: -31.977, lon: -64.352)))
        #expect(!a.contains(Coordinate(lat: -54.8, lon: -68.3)))      // Ushuaia
        #expect(capRegion(url) == "Llanura")
    }

    @Test func shortTermNotice() throws {
        let url = URL(string: "https://ssl.smn.gob.ar/feeds/CAP/avisocortoplazo/2026_11_16_2255_cap_es.xml")!
        let a = try #require(CAPParser.parse(try fixture("aviso-corto-plazo"), url: url))
        #expect(a.event == "TORMENTAS SEVERAS")
        #expect(a.level == .orange)
        #expect(a.levelLabel == "Aviso naranja")
        #expect(a.isShortTerm)
        #expect(a.mentionsHail)
        #expect(a.symbolName == "exclamationmark.triangle.fill")
        #expect(a.contains(Coordinate(lat: -32.481, lon: -61.81)))
    }
}

@Suite("Disk store")
struct DiskStoreTests {
    @Test func savesLoadsAndPrunesRealFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "SMNCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DiskCAPStore(directory: dir)
        let a = capURL("1"), b = capURL("2", shortTerm: true)
        store.save(Data("A".utf8), for: a)
        store.save(Data("B".utf8), for: b)
        #expect(store.load(a) == Data("A".utf8))
        #expect(store.load(b) == Data("B".utf8))

        store.prune(keeping: [b])
        #expect(store.load(a) == nil)
        #expect(store.load(b) == Data("B".utf8))
    }
}

@Suite("Alarm policy")
struct AlarmPolicyTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        return c
    }
    func at(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: hour))!
    }

    @Test func defaultsSoundAndRepeat() {
        #expect(AlarmPolicy().reaction(to: .yellow, at: at(3), calendar: calendar) == .sound(repeating: true))
    }

    @Test func soundOffOnlyBlinks() {
        let p = AlarmPolicy(soundEnabled: false)
        #expect(p.reaction(to: .red, at: at(12), calendar: calendar) == .blinkOnly)
    }

    @Test func singleSoundWhenNotRepeating() {
        let p = AlarmPolicy(repeatUntilSeen: false)
        #expect(p.reaction(to: .orange, at: at(12), calendar: calendar) == .sound(repeating: false))
    }

    @Test(arguments: [(23, true), (2, true), (6, true), (7, false), (12, false), (22, false)])
    func quietYellowAtNight(hour: Int, quiet: Bool) {
        let p = AlarmPolicy(quietYellowAtNight: true)
        #expect((p.reaction(to: .yellow, at: at(hour), calendar: calendar) == .blinkOnly) == quiet)
        #expect(p.reaction(to: .orange, at: at(hour), calendar: calendar) == .sound(repeating: true))   // never quiet
    }
}
