// Sources/OpenTab/FuzzyMatch.swift
import Foundation

/// Subsequence scoring for type-to-filter: rewards consecutive hits and matches
/// right after a word boundary so contiguous/prefix matches outrank scattered ones.
enum FuzzyMatch {
    /// The match score for `query` against `candidate` (both already lowercased),
    /// or nil when `query` is not a subsequence of `candidate`.
    static func score(_ candidate: String, query: String) -> Int? {
        let target = Array(query)
        guard !target.isEmpty else { return 0 }
        var matched = 0
        var score = 0
        var consecutive = 0
        var afterBoundary = true
        for character in candidate {
            if matched < target.count && character == target[matched] {
                score += 1 + consecutive * 4 + (afterBoundary ? 8 : 0)
                consecutive += 1
                matched += 1
            } else {
                consecutive = 0
            }
            afterBoundary = character == " " || character == "-" || character == "_" || character == "."
        }
        return matched == target.count ? score : nil
    }
}
