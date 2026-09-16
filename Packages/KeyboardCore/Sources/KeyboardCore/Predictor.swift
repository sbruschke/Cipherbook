import Foundation

/// What comes before the word being typed, as far as the language model cares.
public enum WordContext: Equatable {
    /// Start of the text or of a sentence.
    case sentenceStart
    /// The previous word, lowercased.
    case after(String)
    /// Something the model has no row for (a comma, a number, an unknown word).
    case unknown

    /// Reads the context from the text before the caret. `currentWord` is the
    /// partial word being typed, already part of `before`, and is skipped.
    public static func from(before: String?, currentWord: String?) -> WordContext {
        var text = Substring(before ?? "")
        if let current = currentWord, text.hasSuffix(current) { text = text.dropLast(current.count) }
        let trimmed = text.reversed().drop { $0 == " " || $0 == "\t" }
        guard let last = trimmed.first else { return .sentenceStart }
        if last.isNewline || ".!?".contains(last) { return .sentenceStart }
        guard last.isLetter || last == "'" || last == "\u{2019}" else { return .unknown }
        let word = String(trimmed.prefix { $0.isLetter || $0 == "'" || $0 == "\u{2019}" }.reversed())
        return .after(Lexicon.normalize(word))
    }
}

/// Ranks words with a unigram model interpolated with the bigram table.
public struct Predictor {
    public let lexicon: Lexicon
    /// Weight of the bigram estimate against the unigram one when both exist.
    public var bigramWeight: Float = 0.7

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
    }

    /// ln P(word | context); nil for words the lexicon doesn't know.
    public func score(_ id: Int, context: WordContext) -> Float {
        let unigram = lexicon.logFrequency(id)
        guard let row = bigramRow(for: context) else { return unigram }
        guard let bigram = lexicon.followers(of: row.id).first(where: { $0.id == id })?.logP else {
            return log(1 - bigramWeight) + unigram
        }
        return log(bigramWeight * exp(bigram) + (1 - bigramWeight) * exp(unigram))
    }

    public func score(_ word: String, context: WordContext) -> Float? {
        lexicon.id(of: word).map { score($0, context: context) }
    }

    /// Words starting with `prefix`, best first, excluding `prefix` itself.
    public func completions(prefix: String, context: WordContext, limit: Int) -> [String] {
        let range = lexicon.prefixRange(prefix)
        guard !prefix.isEmpty, !range.isEmpty, limit > 0 else { return [] }
        let exact = lexicon.id(of: prefix)
        var best: [(id: Int, score: Float)] = []
        func consider(_ id: Int, _ score: Float) {
            guard id != exact else { return }
            if best.count < limit {
                best.append((id, score))
                best.sort { $0.score > $1.score }
            } else if let worst = best.last, score > worst.score {
                best[best.count - 1] = (id, score)
                best.sort { $0.score > $1.score }
            }
        }
        // Unigram pass over the whole prefix range (with the same interpolation discount
        // `score` applies to non-followers), then let the context lift its followers.
        let row = bigramRow(for: context)
        let discount = row == nil ? 0 : log(1 - bigramWeight)
        for id in range { consider(id, discount + lexicon.logFrequency(id)) }
        if let row {
            for follower in lexicon.followers(of: row.id) where range.contains(follower.id) {
                best.removeAll { $0.id == follower.id }
                consider(follower.id, score(follower.id, context: context))
            }
        }
        return best.map { lexicon.word($0.id) }
    }

    /// What is likely to be typed next, for an empty current word.
    public func nextWords(context: WordContext, limit: Int) -> [String] {
        guard let row = bigramRow(for: context) else { return [] }
        return lexicon.followers(of: row.id).prefix(limit).map { lexicon.word($0.id) }
    }

    /// Orders `candidates` by score, known words first, keeping the input order for ties
    /// and for words the lexicon doesn't know.
    public func rank(_ candidates: [String], context: WordContext) -> [String] {
        candidates.enumerated()
            .map { (index: $0.offset, word: $0.element, score: score($0.element, context: context)) }
            .sorted { a, b in
                switch (a.score, b.score) {
                case let (x?, y?) where x != y: return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return a.index < b.index
                }
            }
            .map(\.word)
    }

    /// A row of the bigram table; `id` is nil for the sentence-start row.
    private struct Row { let id: Int? }

    /// The bigram row for a context, or nil when the model has none for it.
    private func bigramRow(for context: WordContext) -> Row? {
        switch context {
        case .sentenceStart: return Row(id: nil)
        case .after(let word): return lexicon.id(of: word).map { Row(id: $0) }
        case .unknown: return nil
        }
    }
}
