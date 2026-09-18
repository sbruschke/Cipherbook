import KeyboardCore
import UIKit

/// English suggestions for the keyboard. Third-party keyboards get no access
/// to the system's predictive text, so this combines a bundled word list and
/// next-word table (`KeyboardCore`) with UITextChecker, which still supplies
/// spelling guesses and anything the user taught it, plus the user's text
/// replacements from the supplementary lexicon.
final class SuggestionEngine {
    struct Result {
        /// What autocorrect would substitute on space, if anything.
        var correction: String?
        var options: [String] = []
    }

    /// Log-probability given up per place in UITextChecker's guess list, so a
    /// far-off frequent word doesn't beat the nearest edit on frequency alone.
    private static let guessOrderPenalty: Float = 1.5

    private let checker = UITextChecker()
    private let language: String
    private var shortcuts: [String: String] = [:]

    /// Nil if the bundled lexicon is missing or unreadable; everything then falls
    /// back to UITextChecker alone, as before.
    private let predictor: Predictor?
    private let decoder: SwipeDecoder?

    init() {
        let available = UITextChecker.availableLanguages
        language = ["en_US", "en_GB", "en"].first(where: { available.contains($0) })
            ?? available.first(where: { $0.hasPrefix("en") })
            ?? "en_US"
        let lexicon = Bundle(for: SuggestionEngine.self).url(forResource: "lexicon", withExtension: "dat")
            .flatMap { try? Lexicon(url: $0) }
        predictor = lexicon.map { Predictor(lexicon: $0) }
        decoder = predictor.map { SwipeDecoder(predictor: $0) }
    }

    var canSwipe: Bool { decoder != nil }

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

    func context(before: String?, currentWord: String?) -> WordContext {
        WordContext.from(before: before, currentWord: currentWord)
    }

    func suggest(for word: String, context: WordContext) -> Result {
        let range = NSRange(location: 0, length: (word as NSString).length)
        var result = Result()

        if let expansion = shortcuts[word.lowercased()] {
            result.correction = expansion
        } else if word == "i" {
            result.correction = "I"
        }

        let misspelled = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0,
                                                       wrap: false, language: language).location != NSNotFound
        // Nothing but "i" may silently re-case a word the dictionary knows. The
        // supplementary lexicon holds contact names and text replacements, so
        // "a" matches an entry for "A" and every article came back capitalised.
        // The capitalised form stays on the bar to be tapped.
        if word != "i", let fix = result.correction, !misspelled,
           SuggestionRules.isCaseOnlyChange(fix, of: word) {
            result.correction = nil
            result.options.append(fix)
        }
        if misspelled {
            var guesses = checker.guesses(forWordRange: range, in: word, language: language) ?? []
            if let predictor {
                guesses = predictor.rank(guesses, context: context, positionPenalty: Self.guessOrderPenalty)
            }
            guesses = guesses.map { matchCase(display($0), to: word) }
            if result.correction == nil, word.count > 1 { result.correction = guesses.first }
            result.options += guesses.dropFirst()
        }

        if let predictor {
            result.options += predictor.completions(prefix: word, context: context, limit: 4)
                .map { matchCase(display($0), to: word) }
        }
        // Words the user taught the system aren't in the bundled list.
        let taught = checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
        result.options += taught
            .filter { $0.caseInsensitiveCompare(word) != .orderedSame }
            .filter { predictor?.lexicon.id(of: $0) == nil }
            .prefix(predictor == nil ? 4 : 2)
            .map { matchCase($0, to: word) }
        return result
    }

    /// Likely next words once the current word is finished.
    func nextWords(context: WordContext, capitalized: Bool) -> [String] {
        (predictor?.nextWords(context: context, limit: 3) ?? []).map {
            capitalized ? capitalize(display($0)) : display($0)
        }
    }

    /// Words for a finger path over the letter keys, best first.
    func swipe(path: [CGPoint], keys: [Character: CGPoint], keyWidth: CGFloat,
               context: WordContext) -> [String] {
        guard let decoder else { return [] }
        return decoder.decode(path: path.map { Point(x: $0.x, y: $0.y) },
                              keys: keys.mapValues { Point(x: $0.x, y: $0.y) },
                              keyWidth: keyWidth, context: context, limit: 3)
            .map(display)
    }

    /// Warms the lazily built swipe index so the first swipe doesn't pay for it.
    func prepareSwipe() {
        _ = predictor?.lexicon.words(from: 0x61, to: 0x61)
    }

    /// The list is lowercase; "I" and its contractions are always capitalised.
    private func display(_ word: String) -> String {
        word == "i" || word.hasPrefix("i'") ? "I" + word.dropFirst() : word
    }

    func capitalize(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    func matchCase(_ candidate: String, to typed: String) -> String {
        if typed.count > 1, typed == typed.uppercased() { return candidate.uppercased() }
        if typed.first?.isUppercase == true { return capitalize(candidate) }
        return candidate
    }
}
