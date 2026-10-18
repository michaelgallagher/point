import Foundation
import Testing
@testable import VaultKit

struct PropertyDateTests {
    @Test(arguments: ["2026-10-18", "2026-10-18T09:30", "2026-10-18 09:30", "2026-10-18T09:30:15"])
    func roundTripsInTheSameStyle(text: String) throws {
        let value = try #require(PropertyDate.parse(text))
        #expect(PropertyDate.format(value.date, like: value) == text)
    }

    @Test(arguments: ["", "soon", "2026-13-01", "18/10/2026", "2026-10-18T9", "2026-10-18 tomorrow"])
    func rejectsNonDates(text: String) {
        #expect(PropertyDate.parse(text) == nil)
    }

    @Test func newDatesHaveNoTime() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3))!
        #expect(PropertyDate.format(date, like: nil) == "2026-01-02")
    }
}
