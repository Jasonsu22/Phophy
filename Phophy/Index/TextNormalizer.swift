import Foundation
import NaturalLanguage

/// Turns text into the words the keyword index stores and searches for.
///
/// English words are lower-cased and reduced to their dictionary form
/// ("dogs" → "dog", "running" → "run"), so a search matches however the
/// word was written. Chinese has no spaces, so it is split into words with
/// Apple's on-device tokenizer ("建筑工人" → "建筑 工人"). The same steps
/// run on photos and on queries, so the two always agree.
nonisolated enum TextNormalizer {
    /// Words for the index, separated by spaces.
    static func indexText(_ text: String) -> String {
        words(in: text, dropStopWords: false).joined(separator: " ")
    }

    /// The words of a search, without filler such as "a", "the", "with".
    static func queryTerms(_ query: String) -> [String] {
        var seen = Set<String>()
        return words(in: query, dropStopWords: true).filter { seen.insert($0).inserted }
    }

    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { isCJK($0) }
    }

    /// How much text there is, with a Chinese or Japanese character counted
    /// as three letters.
    static func textAmount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (isCJK($1) ? 3 : ($1.properties.isWhitespace ? 0 : 1)) }
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xAC00...0xD7AF: true
        default: false
        }
    }

    private static func words(in text: String, dropStopWords: Bool) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = trimmed
        if containsCJK(trimmed) {
            // Mixed text: let the tagger detect, but make sure Chinese is split.
            tagger.setLanguage(.simplifiedChinese, range: trimmed.startIndex..<trimmed.endIndex)
        } else {
            tagger.setLanguage(.english, range: trimmed.startIndex..<trimmed.endIndex)
        }

        var result: [String] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .lemma, options: options) { tag, range in
            let raw = trimmed[range].lowercased()
            if raw.unicodeScalars.contains(where: isCJK) {
                result.append(raw)
                return true
            }
            let word = (tag?.rawValue.lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? raw
            guard word.count > 1 || word.first?.isNumber == true else { return true }
            if dropStopWords, stopWords.contains(word) || stopWords.contains(raw) { return true }
            result.append(word)
            return true
        }
        return result
    }

    /// Dictionary forms of the words used as verbs in `text` ("riding",
    /// "doing" → "ride", "do"), for telling actions from names and things.
    static func verbs(in text: String) -> Set<String> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !containsCJK(trimmed) else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = trimmed
        tagger.setLanguage(.english, range: trimmed.startIndex..<trimmed.endIndex)
        var found = Set<String>()
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            if tag == .verb {
                found.insert(trimmed[range].lowercased())
                let (lemma, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
                if let lemma { found.insert(lemma.rawValue.lowercased()) }
            }
            return true
        }
        return found
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "in", "on", "at", "to", "for", "with", "by", "from",
        "is", "are", "be", "was", "were", "it", "its", "this", "that", "these", "those", "some",
        "as", "into", "onto", "over", "while", "his", "her", "their", "he", "she", "they", "them",
        "photo", "picture", "image", "pic", "show", "me", "my", "find", "of", "all", "who", "which",
        // Filler verbs and pronouns of questions: "people doing kung fu",
        // "where did I take…". On their own they match random descriptions
        // ("a man doing a trick") and push the real subject down.
        "do", "does", "did", "doing", "done", "have", "has", "had", "having", "get", "got", "getting",
        "i", "we", "you", "our", "your", "us", "there", "where", "when", "what", "any", "about",
        "can", "could", "would", "will", "should", "one", "ones", "something", "someone", "somebody",
        "photos", "pictures", "images", "pics", "shot", "shots",
        "的", "了", "在", "是", "和", "与", "一个", "一张", "照片", "图片", "我", "我的", "有", "做", "正在", "那张", "那个",
    ]
}
