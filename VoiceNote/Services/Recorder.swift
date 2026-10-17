import AVFoundation
import Observation
import Speech

/// 마이크 녹음을 담당한다. 들어온 소리를 파일로 저장하면서 동시에 LiveTranscriber로 보내 텍스트로 바꾼다.
@MainActor
@Observable
final class Recorder {
    enum State {
        case idle, preparing, recording, finishing
    }

    struct Output {
        let startedAt: Date
        let duration: TimeInterval
        let audioFileName: String
        let transcript: LiveTranscriber.Transcript
    }

    enum RecorderError: LocalizedError {
        case microphoneDenied
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "마이크 권한이 없어요. 설정에서 보이스노트의 마이크 접근을 허용해 주세요."
            case .noMicrophone: "사용할 수 있는 마이크를 찾지 못했어요."
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var startedAt: Date?
    /// 현재 입력 음량 (0~1, 화면 표시용)
    private(set) var level: Float = 0
    let transcriber = LiveTranscriber()

    private let engine = AVAudioEngine()
    private var processor: AudioTapProcessor?
    private var audioFileName: String?

    func start(locale: Locale) async throws {
        guard state == .idle else { return }
        state = .preparing
        do {
            try await begin(locale: locale)
            state = .recording
        } catch {
            await cancel()
            throw error
        }
    }

    /// 녹음을 끝내고, 마지막 문장까지 인식이 끝나면 결과를 돌려준다.
    func stop() async -> Output? {
        guard state == .recording, let startedAt, let audioFileName else { return nil }
        state = .finishing
        let duration = Date.now.timeIntervalSince(startedAt)
        stopAudio()
        let transcript = await transcriber.finish()
        self.startedAt = nil
        self.audioFileName = nil
        state = .idle
        return Output(startedAt: startedAt, duration: duration, audioFileName: audioFileName, transcript: transcript)
    }

    /// 녹음을 버린다. 저장 중이던 파일도 지운다.
    func cancel() async {
        stopAudio()
        await transcriber.cancel()
        if let audioFileName {
            try? FileManager.default.removeItem(at: Recording.directory.appending(path: audioFileName))
        }
        audioFileName = nil
        startedAt = nil
        state = .idle
    }

    private func begin(locale: Locale) async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderError.microphoneDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let input = try await transcriber.start(locale: locale)
        // 준비하는 동안(모델 다운로드 등) 사용자가 취소했으면 여기서 멈춘다.
        guard state == .preparing else { throw CancellationError() }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noMicrophone
        }

        let fileName = UUID().uuidString + ".m4a"
        let file = try AVAudioFile(
            forWriting: Recording.directory.appending(path: fileName),
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ],
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )
        audioFileName = fileName

        let processor = AudioTapProcessor(file: file, inputFormat: inputFormat, input: input) { [weak self] level in
            Task { @MainActor in self?.level = level }
        }
        self.processor = processor

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: processor.process)
        engine.prepare()
        try engine.start()
        startedAt = .now
    }

    private func stopAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        processor?.close()
        processor = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// 오디오 스레드에서 호출된다. 받은 소리를 파일에 쓰고, 음성 인식기가 원하는 형식으로 바꿔 넘긴다.
private final class AudioTapProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private let input: LiveTranscriber.Input
    private let converter: AVAudioConverter?
    private let onLevel: @Sendable (Float) -> Void

    init(
        file: AVAudioFile,
        inputFormat: AVAudioFormat,
        input: LiveTranscriber.Input,
        onLevel: @escaping @Sendable (Float) -> Void
    ) {
        self.file = file
        self.input = input
        self.onLevel = onLevel
        if inputFormat == input.format {
            converter = nil
        } else {
            converter = AVAudioConverter(from: inputFormat, to: input.format)
            // 앞부분을 건너뛰지 않도록 프라이밍을 끈다.
            converter?.primeMethod = .none
        }
    }

    func process(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }

        try? file.write(from: buffer)
        if let converted = convert(buffer) {
            input.continuation.yield(AnalyzerInput(buffer: converted))
        }
        onLevel(Self.level(of: buffer))
    }

    /// 파일을 닫아 녹음을 마무리한다. 이후 들어오는 소리는 무시한다.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        file?.close()
        file = nil
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// 버퍼의 음량을 0~1 값으로 바꾼다 (-50dB → 0, 0dB → 1).
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count {
            sum += samples[i] * samples[i]
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 50) / 50, 0), 1)
    }
}
