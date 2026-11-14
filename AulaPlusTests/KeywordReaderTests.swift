import XCTest
@testable import AulaPlus

final class KeywordReaderTests: XCTestCase {
    private var friday: Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = AulaDate.copenhagen
        return c.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 9))!
    }

    private func day(_ d: Date?) -> String? {
        guard let d else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AulaDate.copenhagen
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    func testFindsThingsToBringWithDay() {
        let found = KeywordReader.read("Kære forældre. Vi har haft en dejlig uge. Husk gummistøvler og regntøj på mandag!", sentAt: friday)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.title, "Gummistøvler og regntøj på mandag")
        XCTAssertEqual(day(found.first?.due), "2026-11-16")
    }

    func testReadsDates() {
        XCTAssertEqual(day(KeywordReader.date(in: "tilmelding senest d. 20/11", sentAt: friday)), "2026-11-20")
        XCTAssertEqual(day(KeywordReader.date(in: "betal senest 3. december", sentAt: friday)), "2026-12-03")
        XCTAssertEqual(day(KeywordReader.date(in: "hent i morgen kl 14", sentAt: friday)), "2026-11-14")
        XCTAssertEqual(day(KeywordReader.date(in: "svar senest 5/1", sentAt: friday)), "2027-01-05")
    }

    func testIgnoresPlainNews() {
        XCTAssertTrue(KeywordReader.read("I dag har vi bagt boller. Børnene hyggede sig i sandkassen.", sentAt: friday).isEmpty)
    }
}
