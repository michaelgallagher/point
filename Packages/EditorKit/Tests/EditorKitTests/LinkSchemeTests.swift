import Foundation
import Testing
@testable import EditorKit

/// From the review of 27 October: any kind of link opened in whatever app claimed it, so a
/// note from somewhere else could start something with one click. Only web pages and email
/// open without asking.
struct LinkSchemeTests {
    @Test func webPagesAndEmailOpenWithoutAsking() throws {
        for address in ["https://example.com", "http://example.com/a?b", "HTTPS://EXAMPLE.COM", "mailto:ann@example.com"] {
            #expect(LinkTarget.opensWithoutAsking(try #require(URL(string: address))), "\(address)")
        }
    }

    @Test func otherAddressesAsk() throws {
        for address in ["obsidian://open?vault=Notes", "shortcuts://run-shortcut?name=x", "zoommtg://zoom.us/join", "ftp://example.com", "javascript:alert(1)"] {
            #expect(!LinkTarget.opensWithoutAsking(try #require(URL(string: address))), "\(address)")
        }
    }
}
