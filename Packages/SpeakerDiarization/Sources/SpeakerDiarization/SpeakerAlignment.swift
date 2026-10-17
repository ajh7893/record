import Foundation

/// 시간 정보가 붙은 텍스트 조각 (음성 인식 결과의 단어 하나)
public struct TimedText: Codable, Sendable, Hashable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// 화자 한 명이 이어서 한 말
public struct SpeakerLine: Codable, Sendable, Hashable {
    /// 0부터 시작하는 화자 번호 (먼저 말한 사람이 0)
    public var speaker: Int
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(speaker: Int, text: String, start: TimeInterval, end: TimeInterval) {
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
    }
}

/// 음성 인식의 단어 시간과 화자 구분의 구간 시간을 맞춰, 누가 무슨 말을 했는지 묶는다.
public enum SpeakerAlignment {
    public static func lines(words: [TimedText], turns: [SpeakerTurn]) -> [SpeakerLine] {
        guard !words.isEmpty else { return [] }
        guard !turns.isEmpty else {
            return [SpeakerLine(speaker: 0, text: joined(words), start: words[0].start, end: words[words.count - 1].end)]
        }

        var lines: [SpeakerLine] = []
        var current: [TimedText] = []
        var currentSpeaker = -1

        for word in words {
            let speaker = speaker(for: word, in: turns)
            if speaker != currentSpeaker, !current.isEmpty {
                lines.append(line(speaker: currentSpeaker, words: current))
                current = []
            }
            currentSpeaker = speaker
            current.append(word)
        }
        lines.append(line(speaker: currentSpeaker, words: current))

        return renumbered(lines.filter { !$0.text.isEmpty })
    }

    /// 기존 화자 번호 → 처음 말한 순서대로 매긴 새 번호(0, 1, 2…)
    public static func speakerOrder(_ lines: [SpeakerLine]) -> [Int: Int] {
        var order: [Int: Int] = [:]
        for line in lines where order[line.speaker] == nil {
            order[line.speaker] = order.count
        }
        return order
    }

    /// 화자 번호를 처음 말한 순서대로 0, 1, 2…로 다시 매기고, 같은 사람이 연달아 한 말은 합친다.
    public static func renumbered(_ lines: [SpeakerLine]) -> [SpeakerLine] {
        let order = speakerOrder(lines)
        var merged: [SpeakerLine] = []
        for var line in lines {
            line.speaker = order[line.speaker]!
            // 같은 사람이 연달아 말한 줄은 하나로 합친다.
            if let last = merged.last, last.speaker == line.speaker {
                merged[merged.count - 1] = SpeakerLine(
                    speaker: last.speaker, text: last.text + " " + line.text, start: last.start, end: line.end)
            } else {
                merged.append(line)
            }
        }
        return merged
    }

    /// 단어와 가장 많이 겹치는 구간의 화자. 겹치는 구간이 없으면 가장 가까운 구간의 화자.
    private static func speaker(for word: TimedText, in turns: [SpeakerTurn]) -> Int {
        var best: (speaker: Int, overlap: TimeInterval)?
        for turn in turns {
            let overlap = min(word.end, turn.end) - max(word.start, turn.start)
            if overlap > 0, overlap > (best?.overlap ?? 0) {
                best = (turn.speaker, overlap)
            }
        }
        if let best { return best.speaker }

        let middle = (word.start + word.end) / 2
        return turns.min { distance(middle, $0) < distance(middle, $1) }!.speaker
    }

    private static func distance(_ time: TimeInterval, _ turn: SpeakerTurn) -> TimeInterval {
        if time < turn.start { return turn.start - time }
        if time > turn.end { return time - turn.end }
        return 0
    }

    private static func line(speaker: Int, words: [TimedText]) -> SpeakerLine {
        SpeakerLine(speaker: speaker, text: joined(words), start: words[0].start, end: words[words.count - 1].end)
    }

    private static func joined(_ words: [TimedText]) -> String {
        words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
