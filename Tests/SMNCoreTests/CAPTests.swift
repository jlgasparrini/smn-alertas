import Foundation
import Testing
@testable import SMNCore

@Suite("CAP parsing")
struct CAPTests {
    @Test func parsesPrefixedNamespace() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?><cap:alert xmlns:cap="urn:oasis:names:tc:emergency:cap:1.2">
        <cap:identifier>id-1</cap:identifier><cap:info><cap:event>TORMENTAS FUERTES</cap:event><cap:severity>Severe</cap:severity>
        <cap:expires>2026-11-16T16:43:00-03:00</cap:expires><cap:headline>AVISO NARANJA POR TORMENTAS</cap:headline>
        <cap:area><cap:polygon>-33.72,-64.87 -33.93,-65.76 -33.30,-65.84 -33.07,-64.96 -33.72,-64.87</cap:polygon></cap:area>
        </cap:info></cap:alert>
        """
        let a = try #require(CAPParser.parse(Data(xml.utf8)))
        #expect(a.identifier == "id-1")
        #expect(a.level == .orange)
        #expect(a.contains(Coordinate(lat: -33.5, lon: -65.3)))
        #expect(!a.contains(riocuarto))                  // the city is just east of this polygon
        let iso = ISO8601DateFormatter()
        #expect(a.isActive(at: iso.date(from: "2026-11-16T16:00:00-03:00")!))
        #expect(!a.isActive(at: iso.date(from: "2026-11-16T17:00:00-03:00")!))
    }

    @Test func parsesDefaultNamespaceAndEntities() throws {
        let a = try #require(CAPParser.parse(capXML(id: "id-2")))
        #expect(a.level == .yellow)
        #expect(a.contains(riocuarto))
        let accented = Data(#"<alert><info><description>Lluvia &#xE1;</description></info></alert>"#.utf8)
        #expect(CAPParser.parse(accented)?.description == "Lluvia á")
    }

    @Test func rejectsNonCAP() {
        #expect(CAPParser.parse(Data("<html></html>".utf8)) == nil)
        #expect(CAPParser.parse(Data("Demasiadas solicitudes".utf8)) == nil)
    }

    @Test func feedLinksAreDedupedAndLimitedToSMN() {
        let html = #"<a href="https://ssl.smn.gob.ar/feeds/CAP/x/1.xml">a</a><link>https://ssl.smn.gob.ar/feeds/CAP/x/1.xml</link><a href="https://evil.com/feeds/CAP/2.xml">c</a>"#
        #expect(capLinks(in: html).map(\.lastPathComponent) == ["1.xml"])
    }

    @Test func regionFromFileName() {
        #expect(capRegion(capURL("1", region: "Patagonia")) == "Patagonia")
        #expect(capRegion(capURL("1", shortTerm: true)) == nil)
    }
}

@Suite("Levels and icons")
struct LevelTests {
    @Test(arguments: [("Moderate", "", AlertLevel.yellow), ("Severe", "", .orange), ("Extreme", "", .red),
                      ("Moderate", "AVISO NARANJA POR TORMENTAS", .orange), ("Minor", "ALERTA ROJA", .red)])
    func levelFromSeverityAndHeadline(severity: String, headline: String, expected: AlertLevel) {
        #expect(AlertLevel(severity: severity, headline: headline) == expected)
    }

    @Test func labelsAgreeInGender() {
        #expect(alert("1", "Tormentas", "Moderate").levelLabel == "Alerta amarilla")
        #expect(alert("2", "Tormentas", "Extreme").levelLabel == "Alerta roja")
        #expect(alert("3", "Tormentas", "Moderate", shortTerm: true).levelLabel == "Aviso amarillo")
        #expect(alert("4", "Tormentas", "Severe", shortTerm: true).levelLabel == "Aviso naranja")
    }

    @Test(arguments: [("Tormentas", "cloud.bolt.rain"), ("Nevadas", "snowflake"), ("Viento Zonda", "wind"),
                      ("Viento", "wind"), ("Lluvias", "cloud.heavyrain"), ("Otra cosa", "cloud")])
    func symbolPerPhenomenon(event: String, symbol: String) {
        #expect(alert("1", event, "Moderate").symbolName == symbol)
    }

    @Test func mostSevereWinsAndShortTermBreaksTies() {
        let wind = alert("1", "Viento", "Severe"), storm = alert("2", "Tormentas", "Moderate")
        let notice = alert("3", "TORMENTAS FUERTES", "Severe", shortTerm: true)
        #expect(mostSevere([]) == nil)
        #expect(mostSevere([storm, wind])?.id == "1")
        #expect(mostSevere([wind, notice])?.symbolName == "exclamationmark.triangle.fill")
    }
}

@Suite("Notification policy")
struct NotificationPolicyTests {
    @Test func notifiesOncePerEventAndAgainOnlyWhenRising() {
        var r = alertsToNotify(active: [alert("1", "Tormentas", "Moderate"), alert("2", "Tormentas", "Moderate")], previous: [:])
        #expect(r.notify.count == 1)
        #expect(r.state == ["TORMENTAS": .yellow])

        r = alertsToNotify(active: [alert("3", "Tormentas", "Moderate")], previous: r.state)   // SMN update, new id
        #expect(r.notify.isEmpty)

        r = alertsToNotify(active: [alert("4", "Tormentas", "Severe")], previous: r.state)     // escalation
        #expect(r.notify.map(\.id) == ["4"])

        r = alertsToNotify(active: [alert("5", "Tormentas", "Moderate")], previous: r.state)   // downgrade: quiet
        #expect(r.notify.isEmpty)

        r = alertsToNotify(active: [], previous: r.state)                                        // ended
        #expect(r.state.isEmpty)
        r = alertsToNotify(active: [alert("6", "Tormentas", "Moderate")], previous: r.state)   // back again
        #expect(r.notify.count == 1)
    }

    @Test func shortTermNoticesAreTrackedSeparately() {
        let r = alertsToNotify(active: [alert("1", "Tormentas", "Moderate"), alert("2", "TORMENTAS", "Severe", shortTerm: true)],
                               previous: ["TORMENTAS": .yellow])
        #expect(r.notify.map(\.id) == ["2"])
    }
}

@Suite("Display text")
struct DisplayTextTests {
    @Test func sentenceCasesAllCapsOnly() {
        #expect(sentenceCased("TORMENTAS FUERTES CON CAIDA DE GRANIZO") == "Tormentas fuertes con caida de granizo")
        #expect(sentenceCased("Tormentas") == "Tormentas")
        #expect(sentenceCased("") == "")
    }

    @Test func numberedInstructionsBecomeSteps() {
        var a = CAPAlert()
        a.instruction = "1- Evitá salir. 2- No saques la basura y limpiá desagües. 3- Desconectá los electrodomésticos"
        #expect(a.instructionSteps == ["Evitá salir", "No saques la basura y limpiá desagües", "Desconectá los electrodomésticos"])
    }

    @Test func sentenceInstructionsBecomeSteps() {
        var a = CAPAlert()
        a.instruction = "Retirá objetos sueltos. Cerrá y alejate de ventanas. Permanecé en lugares cerrados."
        #expect(a.instructionSteps == ["Retirá objetos sueltos", "Cerrá y alejate de ventanas", "Permanecé en lugares cerrados"])
    }

    @Test func realAlertInstructionsSplit() throws {
        let url = try #require(Bundle.module.url(forResource: "alerta", withExtension: "xml", subdirectory: "Fixtures"))
        let a = try #require(CAPParser.parse(try Data(contentsOf: url)))
        #expect(a.instructionSteps.count >= 3)
        #expect(a.instructionSteps.allSatisfy { !$0.first!.isNumber })
    }
}
