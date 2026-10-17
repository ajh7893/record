import Foundation
import SpeakerDiarization
import SwiftData

/// 저장된 녹음 하나. 오디오 파일은 Documents/Recordings 폴더에 따로 저장되고, 여기에는 파일 이름만 기록한다.
@Model
final class Recording {
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String
    var audioFileName: String
    /// 녹음할 때 쓴 인식 언어 (예: "ko-KR")
    var languageID: String = TranscriptionLanguage.defaultID
    /// 단어별 시간 정보. 화자 구분 결과와 맞출 때 쓴다.
    var words: [TimedText] = []
    /// 화자 구분 결과 (비어 있으면 아직 구분하지 않음)
    var speakerLines: [SpeakerLine] = []
    /// 화자 번호별로 사용자가 붙인 이름
    var speakerNames: [Int: String] = [:]

    init(
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        transcript: String,
        audioFileName: String,
        languageID: String = TranscriptionLanguage.defaultID,
        words: [TimedText] = []
    ) {
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
        self.audioFileName = audioFileName
        self.languageID = languageID
        self.words = words
    }

    var audioURL: URL {
        Recording.directory.appending(path: audioFileName)
    }

    /// 화자 번호 순서대로 (0, 1, 2…)
    var speakers: [Int] {
        Array(Set(speakerLines.map(\.speaker))).sorted()
    }

    func speakerName(_ speaker: Int) -> String {
        speakerNames[speaker] ?? "화자 \(speaker + 1)"
    }

    /// 화자 하나를 다른 화자로 합친다. 번호는 처음 말한 순서대로 다시 매긴다.
    func mergeSpeaker(_ source: Int, into target: Int) {
        var lines = speakerLines
        for index in lines.indices where lines[index].speaker == source {
            lines[index].speaker = target
        }
        let order = SpeakerAlignment.speakerOrder(lines)
        speakerNames = Dictionary(uniqueKeysWithValues: speakerNames.compactMap { speaker, name in
            order[speaker].map { ($0, name) }
        })
        speakerLines = SpeakerAlignment.renumbered(lines)
    }

    /// 복사·공유용 텍스트. 화자를 구분했으면 "이름: 말" 형식으로 만든다.
    var shareText: String {
        guard !speakerLines.isEmpty else { return transcript }
        return speakerLines
            .map { "\(speakerName($0.speaker)): \($0.text)" }
            .joined(separator: "\n\n")
    }

    /// 녹음 파일과 함께 삭제한다.
    func deleteWithAudio(in context: ModelContext) {
        try? FileManager.default.removeItem(at: audioURL)
        context.delete(self)
    }

    static var directory: URL {
        let url = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func defaultTitle(for date: Date) -> String {
        "녹음 " + date.formatted(.dateTime.month().day().hour().minute())
    }
}

extension TimeInterval {
    /// 65초 → "1:05", 3725초 → "1:02:05"
    var clockText: String {
        Duration.seconds(self).formatted(.time(pattern: self >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
