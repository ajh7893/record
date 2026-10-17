import AVFoundation
import Observation
import SpeakerDiarization
import Speech

/// 애플의 SpeechAnalyzer(iOS 26+)로 오디오를 실시간으로 텍스트로 바꾼다.
/// 인식은 모두 기기 안에서 이뤄지므로 인터넷이나 유료 API가 필요 없다.
@MainActor
@Observable
final class LiveTranscriber {
    enum TranscriberError: LocalizedError {
        case unsupportedLanguage
        case noAudioFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedLanguage: "이 기기에서는 선택한 언어의 음성 인식을 지원하지 않아요."
            case .noAudioFormat: "음성 인식에 사용할 오디오 형식을 찾지 못했어요."
            }
        }
    }

    /// 오디오를 넣을 입구와, 그 입구가 기대하는 오디오 형식
    struct Input {
        let continuation: AsyncStream<AnalyzerInput>.Continuation
        let format: AVAudioFormat
    }

    /// 녹음이 끝난 뒤의 인식 결과
    struct Transcript {
        let text: String
        /// 단어별 시간 정보 (화자 구분에 쓴다)
        let words: [TimedText]
    }

    /// 확정된 텍스트
    private(set) var finalizedText = ""
    /// 아직 인식 중이라 바뀔 수 있는 텍스트
    private(set) var volatileText = ""
    /// 음성 인식 모델을 내려받는 중인지 (언어별로 처음 한 번만)
    private(set) var isDownloadingModel = false

    private var words: [TimedText] = []
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    func start(locale: Locale) async throws -> Input {
        finalizedText = ""
        volatileText = ""
        words = []

        guard let module = await Self.makeModule(for: locale) else {
            throw TranscriberError.unsupportedLanguage
        }
        defer { isDownloadingModel = false }
        try await Self.installModelIfNeeded(for: module) { isDownloadingModel = true }
        isDownloadingModel = false

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriberError.noAudioFormat
        }

        let analyzer = SpeechAnalyzer(modules: [module])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        resultsTask = Task { [weak self] in
            do {
                try await Self.forEachResult(of: module) { text, isFinal in
                    self?.receive(text, isFinal: isFinal)
                }
            } catch {
                // 취소하면 여기로 온다. 그때까지 받은 텍스트는 그대로 둔다.
            }
        }

        try await analyzer.start(inputSequence: stream)
        self.analyzer = analyzer
        self.inputContinuation = continuation
        return Input(continuation: continuation, format: format)
    }

    /// 남은 오디오까지 모두 인식한 뒤 최종 결과를 돌려준다.
    func finish() async -> Transcript {
        inputContinuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        finalizedText += volatileText
        volatileText = ""
        reset()
        return Transcript(text: finalizedText.trimmingCharacters(in: .whitespacesAndNewlines), words: words)
    }

    /// 결과를 기다리지 않고 바로 멈춘다.
    func cancel() async {
        inputContinuation?.finish()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        reset()
    }

    /// 저장된 녹음 파일을 처음부터 다시 인식해 단어별 시간 정보를 얻는다.
    /// (시간 정보 없이 저장된 예전 녹음을 화자 구분할 때 쓴다.)
    static func timedWords(fromFile url: URL, locale: Locale) async throws -> [TimedText] {
        guard let module = await makeModule(for: locale) else {
            throw TranscriberError.unsupportedLanguage
        }
        try await installModelIfNeeded(for: module)

        let collecting = Task { () -> [TimedText] in
            var words: [TimedText] = []
            try await forEachResult(of: module) { text, isFinal in
                if isFinal { words += timedWords(in: text) }
            }
            return words
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.start(inputAudioFile: AVAudioFile(forReading: url), finishAfterFile: true)
        return try await collecting.value
    }

    private func receive(_ text: AttributedString, isFinal: Bool) {
        if isFinal {
            finalizedText += String(text.characters)
            volatileText = ""
            words += Self.timedWords(in: text)
        } else {
            volatileText = String(text.characters)
        }
    }

    private func reset() {
        analyzer = nil
        inputContinuation = nil
        resultsTask = nil
    }

    /// 최신 인식기(SpeechTranscriber)를 우선 쓰고, 기기가 지원하지 않으면 받아쓰기 인식기로 대신한다.
    /// 둘 다 단어별 시간 정보(audioTimeRange)를 함께 내도록 설정한다.
    private static func makeModule(for locale: Locale) async -> (any SpeechModule)? {
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return SpeechTranscriber(locale: supported, preset: .timeIndexedProgressiveTranscription)
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return DictationTranscriber(
                locale: supported,
                contentHints: [],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
        }
        return nil
    }

    private static func installModelIfNeeded(
        for module: some SpeechModule,
        onDownloadStart: () -> Void = {}
    ) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        onDownloadStart()
        try await request.downloadAndInstall()
    }

    /// 인식 결과가 나올 때마다 (텍스트, 확정 여부)를 넘겨준다. 인식이 끝나면 돌아온다.
    private static func forEachResult<Module: SpeechModule>(
        of module: Module,
        _ body: (AttributedString, Bool) -> Void
    ) async throws {
        for try await result in module.results {
            body(text(of: result), result.isFinal)
        }
    }

    private static func text(of result: some SpeechModuleResult) -> AttributedString {
        switch result {
        case let result as SpeechTranscriber.Result: result.text
        case let result as DictationTranscriber.Result: result.text
        default: AttributedString()
        }
    }

    /// 인식 결과에서 단어별 시간 정보를 꺼낸다. 시간 정보가 없는 공백·문장부호는 앞 단어에 붙인다.
    static func timedWords(in text: AttributedString) -> [TimedText] {
        var words: [TimedText] = []
        var leading = ""
        for run in text.runs {
            let piece = String(text[run.range].characters)
            if let range = run.audioTimeRange {
                words.append(TimedText(text: leading + piece, start: range.start.seconds, end: range.end.seconds))
                leading = ""
            } else if words.isEmpty {
                leading += piece
            } else {
                words[words.count - 1].text += piece
            }
        }
        return words
    }
}
