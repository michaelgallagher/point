import Foundation
import SwiftUI

/// Counting a note's words quickly enough to do as it's typed in: one pass over the text, a
/// word being a run of characters between spaces or line breaks with a letter or digit in it
/// (so a list's "-", a heading's "#" or a table's "|" aren't counted).
enum WordCount {
    struct Tally: Equatable {
        var total: Int
        /// The words selected, when there's a selection.
        var selected: Int?

        var label: String {
            let total = total.formatted()
            let noun = self.total == 1 ? "word" : "words"
            guard let selected else { return "\(total) \(noun)" }
            return "\(selected.formatted()) of \(total) \(noun)"
        }
    }

    private static let spaces = CharacterSet.whitespacesAndNewlines
    private static let wordy = CharacterSet.alphanumerics

    static func count(_ text: NSString, in range: NSRange) -> Int {
        guard range.length > 0 else { return 0 }
        var buffer = [unichar](repeating: 0, count: range.length)
        text.getCharacters(&buffer, range: range)
        var count = 0
        var inRun = false
        var runHasLetter = false
        for unit in buffer {
            // Surrogate halves (emoji and the like) count as part of a word, not a space.
            let isSpace = Unicode.Scalar(unit).map { spaces.contains($0) } ?? false
            if isSpace {
                if inRun, runHasLetter { count += 1 }
                inRun = false
                runHasLetter = false
            } else {
                inRun = true
                if !runHasLetter { runHasLetter = Unicode.Scalar(unit).map { wordy.contains($0) } ?? true }
            }
        }
        if inRun, runHasLetter { count += 1 }
        return count
    }
}

/// The current note's word count, in the bottom corner the links button leaves free (View ›
/// Show Word Count).
struct WordCountLabel: View {
    let tally: WordCount.Tally?
    let alignment: Alignment

    var body: some View {
        if let tally {
            // On glass, as the links button is, so it reads over the text scrolling under it.
            Text(tally.label)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .modifier(LinksGlass(shape: Capsule(), isInteractive: false))
                .padding(LinksButton.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .allowsHitTesting(false)
                .accessibilityLabel(tally.label)
        }
    }
}
