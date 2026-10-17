import FluidAudio
import Foundation

/// 한 사람이 이어서 말한 구간
public struct SpeakerTurn: Sendable, Hashable {
    /// 0부터 시작하는 화자 번호
    public let speaker: Int
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speaker: Int, start: TimeInterval, end: TimeInterval) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// 녹음 파일을 분석해 누가 언제 말했는지 알아낸다. 모든 처리는 기기 안에서 이뤄진다.
/// 처음 쓸 때 화자 구분 모델을 내려받는다 (인터넷 필요, 한 번만).
public actor SpeakerDiarizer {
    private let manager = OfflineDiarizerManager()
    private var preparing: Task<Void, Error>?

    public init() {}

    /// 모델을 준비한다. 없으면 내려받는다. 여러 곳에서 동시에 불러도 한 번만 준비한다.
    public func prepare() async throws {
        if let preparing {
            return try await preparing.value
        }
        let task = Task { try await manager.prepareModels() }
        preparing = task
        do {
            try await task.value
        } catch {
            preparing = nil
            throw error
        }
    }

    /// - Parameter progress: 0~1 진행률
    public func analyze(fileURL: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> [SpeakerTurn] {
        try await prepare()
        let result = try await manager.process(fileURL) { done, total in
            progress?(Double(done) / Double(max(total, 1)))
        }
        return result.segments
            .sorted { $0.startTimeSeconds < $1.startTimeSeconds }
            .map { segment in
                SpeakerTurn(
                    speaker: Self.number(for: segment.speakerId),
                    start: TimeInterval(segment.startTimeSeconds),
                    end: TimeInterval(segment.endTimeSeconds)
                )
            }
    }

    /// "speaker_0", "S1" 같은 ID에서 숫자만 뽑는다. 최종 번호는 SpeakerAlignment가 등장 순서대로 다시 매긴다.
    private static func number(for speakerId: String) -> Int {
        Int(speakerId.filter(\.isNumber)) ?? abs(speakerId.hashValue % 1000)
    }
}
