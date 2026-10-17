import Foundation
import Observation
import SpeakerDiarization

/// 녹음 하나의 화자 구분을 진행하고 결과를 Recording에 저장한다.
///
/// 1. 단어별 시간 정보가 없는 예전 녹음이면 녹음 파일을 다시 인식해 만든다.
/// 2. 화자 구분 모델로 "누가 몇 초부터 몇 초까지 말했는지" 구간을 찾는다.
/// 3. 두 결과를 시간으로 맞춰 "화자: 말" 줄로 묶는다.
@MainActor
@Observable
final class SpeakerAnalysis {
    enum Phase: Equatable {
        case idle
        case transcribing
        case preparingModel
        case analyzing(progress: Double)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    var isRunning: Bool {
        switch phase {
        case .transcribing, .preparingModel, .analyzing: true
        case .idle, .failed: false
        }
    }

    /// 모델은 한 번 불러오면 앱이 켜져 있는 동안 계속 쓴다.
    private static let diarizer = SpeakerDiarizer()

    func run(for recording: Recording) async {
        guard !isRunning else { return }
        do {
            if recording.words.isEmpty {
                phase = .transcribing
                recording.words = try await LiveTranscriber.timedWords(
                    fromFile: recording.audioURL,
                    locale: Locale(identifier: recording.languageID)
                )
            }
            guard !recording.words.isEmpty else {
                phase = .failed("인식된 말소리가 없어서 화자를 구분할 수 없어요.")
                return
            }

            phase = .preparingModel
            try await Self.diarizer.prepare()

            phase = .analyzing(progress: 0)
            let turns = try await Self.diarizer.analyze(fileURL: recording.audioURL) { [weak self] progress in
                Task { @MainActor in
                    if case .analyzing = self?.phase {
                        self?.phase = .analyzing(progress: progress)
                    }
                }
            }

            recording.speakerNames = [:]
            recording.speakerLines = SpeakerAlignment.lines(words: recording.words, turns: turns)
            phase = .idle
        } catch {
            phase = .failed("화자 구분에 실패했어요. 처음 한 번은 모델을 내려받아야 해서 인터넷 연결이 필요해요.\n(\(error.localizedDescription))")
        }
    }
}
