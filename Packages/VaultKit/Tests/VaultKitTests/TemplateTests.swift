import Foundation
import Testing
@testable import VaultKit

struct MomentFormatTests {
    /// Sunday 18 October 2026, 09:05:07 local time.
    let date: Date = {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 10, 18, 9, 5, 7)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    @Test(arguments: [
        ("YYYY-MM-DD", "2026-10-18"),
        ("dddd D MMMM YYYY", "Sunday 18 October 2026"),
        ("ddd Do MMM", "Sun 18th Oct"),
        ("HH:mm:ss", "09:05:07"),
        ("h:mm A", "9:05 AM"),
        ("YY/M/D", "26/10/18"),
        ("[Week] W, GGGG", "Week 42, 2026"),
        ("YYYY/MM/YYYY-MM-DD", "2026/10/2026-10-18"),
        // Moment reads YYY as YY followed by Y (the full year), so Obsidian gives this too.
        ("YYY-MM-DD", "262026-10-18"),
    ])
    func formats(format: String, expected: String) {
        #expect(MomentFormat(format).string(from: date) == expected)
    }
}

struct TemplateRenderTests {
    let date = MomentFormatTests().date

    @Test func fillsInObsidianVariables() {
        var settings = ObsidianSettings()
        settings.templatesDateFormat = "D MMM YYYY"
        let template = "# {{title}}\nCreated {{date}} at {{time}}. Week {{date:W}}. {{ unknown }} <% tp.date.now() %>"
        #expect(Templates.render(template, title: "Plan", date: date, settings: settings)
                == "# Plan\nCreated 18 Oct 2026 at 09:05. Week 42. {{ unknown }} <% tp.date.now() %>")
    }

    @Test func dailyNotesFollowTheSettings() {
        var settings = ObsidianSettings()
        let root = URL(fileURLWithPath: "/vault")
        #expect(Templates.dailyNoteURL(for: date, in: root, settings: settings).path == "/vault/2026-10-18.md")
        settings.dailyNotesFolder = "Daily"
        settings.dailyNotesFormat = "YYYY/MM/DD dddd"
        #expect(Templates.dailyNoteURL(for: date, in: root, settings: settings).path == "/vault/Daily/2026/10/18 Sunday.md")
    }
}
