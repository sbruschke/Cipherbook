import UIKit

/// English suggestions for the keyboard. Third-party keyboards get no access
/// to the system's predictive text, so this uses UITextChecker (the iOS
/// dictionary and anything the user taught it) plus the user's text
/// replacements from the supplementary lexicon.
final class SuggestionEngine {
    struct Result {
        /// What autocorrect would substitute on space, if anything.
        var correction: String?
        var options: [String] = []
    }

    private let checker = UITextChecker()
    private let language: String
    private var shortcuts: [String: String] = [:]

    init() {
        let available = UITextChecker.availableLanguages
        language = ["en_US", "en_GB", "en"].first(where: { available.contains($0) })
            ?? available.first(where: { $0.hasPrefix("en") })
            ?? "en_US"
    }

    func absorb(_ lexicon: UILexicon) {
        for entry in lexicon.entries {
            shortcuts[entry.userInput.lowercased()] = entry.documentText
        }
    }

    func learn(_ word: String) {
        if !UITextChecker.hasLearnedWord(word) { UITextChecker.learnWord(word) }
    }

    /// The run of letters and apostrophes immediately before the caret.
    func currentWord(in context: String?) -> String? {
        guard let context else { return nil }
        let word = String(context.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "\u{2019}" }.reversed())
        return word.isEmpty ? nil : word
    }

    func suggest(for word: String) -> Result {
        let range = NSRange(location: 0, length: (word as NSString).length)
        var result = Result()

        if let expansion = shortcuts[word.lowercased()] {
            result.correction = expansion
        } else if word == "i" {
            result.correction = "I"
        }

        let misspelled = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0,
                                                       wrap: false, language: language).location != NSNotFound
        if misspelled {
            let guesses = (checker.guesses(forWordRange: range, in: word, language: language) ?? [])
                .map { matchCase($0, to: word) }
            if result.correction == nil, word.count > 1 { result.correction = guesses.first }
            result.options += guesses.dropFirst()
        }

        let completions = checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
        result.options += completions
            .filter { $0.caseInsensitiveCompare(word) != .orderedSame }
            .prefix(4)
            .map { matchCase($0, to: word) }
        return result
    }

    private func matchCase(_ candidate: String, to typed: String) -> String {
        if typed.count > 1, typed == typed.uppercased() { return candidate.uppercased() }
        if typed.first?.isUppercase == true { return candidate.prefix(1).uppercased() + candidate.dropFirst() }
        return candidate
    }
}
