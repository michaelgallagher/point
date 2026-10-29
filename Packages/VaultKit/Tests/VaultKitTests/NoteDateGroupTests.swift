import Foundation
import Testing
@testable import VaultKit

/// The headings a note list sorted by date is split under.
struct NoteDateGroupTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var now: Date { date(2026, 10, 28, 9) }

    @Test func labelsByHowLongAgo() {
        #expect(NoteDateGroup.label(for: date(2026, 10, 28, 1), now: now, calendar: calendar) == "Today")
        #expect(NoteDateGroup.label(for: date(2026, 10, 29), now: now, calendar: calendar) == "Today")
        #expect(NoteDateGroup.label(for: date(2026, 10, 27, 23), now: now, calendar: calendar) == "Yesterday")
        #expect(NoteDateGroup.label(for: date(2026, 10, 22), now: now, calendar: calendar) == "Previous 7 Days")
        #expect(NoteDateGroup.label(for: date(2026, 10, 21), now: now, calendar: calendar) == "October")
        #expect(NoteDateGroup.label(for: date(2026, 1, 2), now: now, calendar: calendar) == "January")
        #expect(NoteDateGroup.label(for: date(2025, 12, 31), now: now, calendar: calendar) == "2025")
    }

    @Test func groupsNotesInOrder() {
        func note(_ title: String, modified: Date, created: Date) -> Note {
            Note(id: title + ".md", url: URL(fileURLWithPath: "/v/\(title).md"), title: title, modified: modified, created: created, isDownloaded: true)
        }
        let notes = [
            note("a", modified: date(2026, 10, 28), created: date(2024, 3, 1)),
            note("b", modified: date(2026, 10, 25), created: date(2026, 10, 25)),
            note("c", modified: date(2026, 10, 1), created: date(2026, 10, 1)),
            note("d", modified: date(2026, 9, 30), created: date(2026, 9, 30)),
            note("e", modified: date(2023, 5, 5), created: date(2023, 5, 5)),
        ]
        let byEdited = NoteDateGroup.grouped(notes.sorted(by: .modified), by: .modified, now: now, calendar: calendar)
        #expect(byEdited.map(\.label) == ["Today", "Previous 7 Days", "October", "September", "2023"])
        #expect(byEdited.map { $0.notes.map(\.title) } == [["a"], ["b"], ["c"], ["d"], ["e"]])
        let byCreated = NoteDateGroup.grouped(notes.sorted(by: .created), by: .created, now: now, calendar: calendar)
        #expect(byCreated.map(\.label) == ["Previous 7 Days", "October", "September", "2024", "2023"])
        #expect(NoteDateGroup.grouped(notes, by: .title, now: now, calendar: calendar).isEmpty)
    }
}
