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
            if dropStopWords, stopWords.contains(word) { return true }
            result.append(word)
            return true
        }
        return result
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "in", "on", "at", "to", "for", "with", "by", "from",
        "is", "are", "be", "was", "were", "it", "its", "this", "that", "these", "those", "some",
        "as", "into", "onto", "over", "while", "his", "her", "their", "he", "she", "they", "them",
        "photo", "picture", "image", "pic", "show", "me", "my", "find", "of", "all", "who", "which",
        "的", "了", "在", "是", "和", "与", "一个", "一张", "照片", "图片",
    ]
}
