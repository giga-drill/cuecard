import Foundation

struct MandarinNormalizedToken: Equatable, Sendable {
    let text: String
    let pinyin: String?
}

enum MandarinTextNormalizer {
    static func normalize(_ text: String, removesDeliveryNotes: Bool = true) -> [MandarinNormalizedToken] {
        var source = text
        if removesDeliveryNotes {
            source = removeDeliveryNotes(from: source)
        }
        source = source.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? source
        source = source.applyingTransform(StringTransform("Fullwidth-Halfwidth"), reverse: false) ?? source
        source = source.lowercased()

        return source.compactMap { character in
            guard isAlignmentCharacter(character) else { return nil }
            let token = String(character)
            return MandarinNormalizedToken(
                text: token,
                pinyin: isHan(character) ? pinyin(for: token) : nil
            )
        }
    }

    static func normalizedText(_ text: String, removesDeliveryNotes: Bool = true) -> String {
        normalize(text, removesDeliveryNotes: removesDeliveryNotes).map(\.text).joined()
    }

    private static func removeDeliveryNotes(from text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"\[note\s+[^\]]+\]"#, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private static func isAlignmentCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isAlphabetic || scalar.properties.numericType != nil
        }
    }

    private static func isHan(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }

    private static func pinyin(for token: String) -> String? {
        guard let latin = token.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripCombiningMarks, reverse: false)?
            .lowercased()
            .replacingOccurrences(of: " ", with: ""),
              latin != token,
              !latin.isEmpty else {
            return nil
        }
        return latin
    }
}

struct MandarinAlignment: Equatable, Sendable {
    let tokenIndex: Int
    let progress: Double
    let confidence: Double
    let matchedRange: Range<Int>
}

struct MandarinScriptAlignerConfiguration: Equatable, Sendable {
    var lookBehind = 32
    var lookAhead = 120
    var recognitionWindow = 12
    var minimumRecognitionLength = 4
    var shortWindowMaximumJump = 24
    var acceptanceThreshold = 0.56
}

final class MandarinScriptAligner {
    let scriptTokens: [MandarinNormalizedToken]
    private(set) var currentTokenIndex: Int

    private let configuration: MandarinScriptAlignerConfiguration
    private var lastRecognitionText = ""

    init(
        script: String,
        initialProgress: Double = 0,
        configuration: MandarinScriptAlignerConfiguration = .init()
    ) {
        scriptTokens = MandarinTextNormalizer.normalize(script)
        self.configuration = configuration
        currentTokenIndex = min(
            max(Int(Double(scriptTokens.count) * initialProgress), 0),
            scriptTokens.count
        )
    }

    func reset(to progress: Double = 0) {
        currentTokenIndex = min(max(Int(Double(scriptTokens.count) * progress), 0), scriptTokens.count)
        lastRecognitionText = ""
    }

    func align(recognitionText: String) -> MandarinAlignment? {
        guard !scriptTokens.isEmpty else { return nil }
        let recognitionTokens = MandarinTextNormalizer.normalize(recognitionText, removesDeliveryNotes: false)
        let recognitionKey = recognitionTokens.map(\.text).joined()
        guard recognitionKey != lastRecognitionText else { return nil }
        lastRecognitionText = recognitionKey

        guard recognitionTokens.count >= configuration.minimumRecognitionLength else { return nil }
        let window = Array(recognitionTokens.suffix(configuration.recognitionWindow))
        let windowCount = window.count

        let minimumEnd = max(windowCount, currentTokenIndex - configuration.lookBehind)
        let maximumEnd = min(scriptTokens.count, currentTokenIndex + configuration.lookAhead)
        guard minimumEnd <= maximumEnd else { return nil }

        var best: (end: Int, score: Double)?
        for candidateEnd in minimumEnd...maximumEnd {
            let start = candidateEnd - windowCount
            guard start >= 0 else { continue }
            let candidate = Array(scriptTokens[start..<candidateEnd])
            let score = alignmentScore(recognition: window, candidate: candidate, candidateEnd: candidateEnd)
            if best == nil || score > best!.score {
                best = (candidateEnd, score)
            }
        }

        guard let best, best.score >= configuration.acceptanceThreshold else { return nil }
        let delta = best.end - currentTokenIndex
        if windowCount < 6, abs(delta) > configuration.shortWindowMaximumJump {
            return nil
        }

        currentTokenIndex = best.end
        return MandarinAlignment(
            tokenIndex: best.end,
            progress: min(max(Double(best.end) / Double(scriptTokens.count), 0), 1),
            confidence: best.score,
            matchedRange: (best.end - windowCount)..<best.end
        )
    }

    private func alignmentScore(
        recognition: [MandarinNormalizedToken],
        candidate: [MandarinNormalizedToken],
        candidateEnd: Int
    ) -> Double {
        let recognitionText = recognition.map(\.text)
        let candidateText = candidate.map(\.text)
        let distance = levenshteinDistance(recognitionText, candidateText)
        let length = max(recognition.count, candidate.count)
        let editSimilarity = 1 - Double(distance) / Double(max(length, 1))

        let exactMatches = zip(recognitionText, candidateText).filter(==).count
        let exactRatio = Double(exactMatches) / Double(max(length, 1))

        let suffixMatches = zip(recognition.reversed(), candidate.reversed())
            .prefix { $0.text == $1.text }
            .count
        let suffixRatio = Double(suffixMatches) / Double(max(length, 1))

        let pinyinMatches = zip(recognition, candidate).filter { left, right in
            left.text != right.text && left.pinyin != nil && left.pinyin == right.pinyin
        }.count
        let pinyinRatio = Double(pinyinMatches) / Double(max(length, 1))

        let distanceFromCurrent = abs(candidateEnd - currentTokenIndex)
        let localityPenalty = min(Double(distanceFromCurrent) / Double(max(configuration.lookAhead, 1)), 1) * 0.18
        let backwardPenalty = candidateEnd < currentTokenIndex ? 0.06 : 0
        let forwardBonus = candidateEnd >= currentTokenIndex
            ? min(Double(candidateEnd - currentTokenIndex) / 20, 1) * 0.025
            : 0

        return editSimilarity * 0.58
            + exactRatio * 0.24
            + suffixRatio * 0.18
            + pinyinRatio * 0.06
            + forwardBonus
            - localityPenalty
            - backwardPenalty
    }

    private func levenshteinDistance(_ left: [String], _ right: [String]) -> Int {
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        for (leftIndex, leftValue) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)
            for (rightIndex, rightValue) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftValue == rightValue ? 0 : 1)
                current.append(min(insertion, deletion, substitution))
            }
            previous = current
        }
        return previous[right.count]
    }
}
