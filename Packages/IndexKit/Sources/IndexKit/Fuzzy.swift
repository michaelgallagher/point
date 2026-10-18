import Foundation

/// Forgiving matching for search: typos, partial words, words in any order.
public enum Fuzzy {
    /// How many typos a word of this length may contain and still match.
    static func allowedTypos(for word: String) -> Int {
        switch word.count {
        case ..<4: 0
        case 4...6: 1
        default: 2
        }
    }

    /// The number of single-character edits (insert, delete, substitute, swap neighbours)
    /// between two words, or nil if it is more than `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int? {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= limit else { return nil }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previousPrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], previousPrevious[j - 2] + 1)
                }
                rowMinimum = min(rowMinimum, current[j])
            }
            if rowMinimum > limit { return nil }
            (previousPrevious, previous, current) = (previous, current, previousPrevious)
        }
        return previous[b.count] <= limit ? previous[b.count] : nil
    }

    /// The words of a text, lowercased, split at anything that isn't a letter or digit.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// How well a title matches one query word: 0 is best, nil is no match.
    static func titleScore(word: String, title: String, titleWords: [String]) -> Int? {
        if title.hasPrefix(word) { return 0 }
        if titleWords.contains(where: { $0.hasPrefix(word) }) { return 1 }
        if title.contains(word) { return 2 }
        let typos = allowedTypos(for: word)
        guard typos > 0 else { return nil }
        // A typo in a whole word, or in the start of a longer word being typed.
        for candidate in titleWords {
            if editDistance(word, candidate, limit: typos) != nil { return 3 }
            if candidate.count > word.count, editDistance(word, String(candidate.prefix(word.count)), limit: typos) != nil { return 4 }
        }
        return nil
    }

    /// How well a name matches a query (0 is best), or nil if it doesn't. Every word of the
    /// query must match the start of a word, part of a word, or a word with a typo or two.
    public static func score(query: String, name: String) -> Int? {
        let words = words(query)
        return words.isEmpty ? 0 : titleScore(words: words, title: name)
    }

    /// How well a title matches every query word, or nil if any word fails to match.
    static func titleScore(words: [String], title: String) -> Int? {
        let lowered = title.lowercased()
        let titleWords = Self.words(title)
        var total = 0
        for word in words {
            guard let score = titleScore(word: word, title: lowered, titleWords: titleWords) else { return nil }
            total += score
        }
        return total
    }
}
