import SwiftData
import SwiftUI
import UIKit

/// 녹음 화면: 화면이 열리면 바로 녹음을 시작하고, 말하는 내용을 실시간으로 보여준다.
struct RecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(TranscriptionLanguage.storageKey) private var languageID = TranscriptionLanguage.defaultID
    @State private var recorder = Recorder()
    @State private var errorMessage: String?
    @State private var needsMicrophoneSetting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                status
                transcript
                stopButton
            }
            .padding()
            .navigationTitle("새 녹음")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", role: .cancel) {
                        Task {
                            await recorder.cancel()
                            dismiss()
                        }
                    }
                    .disabled(recorder.state == .finishing)
                }
            }
        }
        .task {
            await start()
        }
        .alert("녹음을 시작할 수 없어요", isPresented: .constant(errorMessage != nil)) {
            if needsMicrophoneSetting {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                    dismiss()
                }
            }
            Button("닫기", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch recorder.state {
        case .idle, .preparing:
            if recorder.transcriber.isDownloadingModel {
                Label("음성 인식 모델을 내려받는 중… (처음 한 번만)", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("준비 중…")
            }
        case .recording:
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let elapsed = recorder.startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                Text(elapsed.clockText)
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
            }
        case .finishing:
            ProgressView("마지막 문장을 정리하는 중…")
        }
    }

    private var transcript: some View {
        ScrollView {
            Group {
                if recorder.transcriber.finalizedText.isEmpty && recorder.transcriber.volatileText.isEmpty {
                    Text(recorder.state == .recording ? "듣고 있어요. 말해 보세요." : "")
                        .foregroundStyle(.tertiary)
                } else {
                    Text(transcriptText)
                }
            }
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .frame(maxHeight: .infinity)
    }

    /// 확정된 텍스트는 진하게, 아직 바뀔 수 있는 텍스트는 흐리게 보여준다.
    private var transcriptText: AttributedString {
        let finalized = AttributedString(recorder.transcriber.finalizedText)
        var volatile = AttributedString(recorder.transcriber.volatileText)
        volatile.foregroundColor = .secondary
        return finalized + volatile
    }

    private var stopButton: some View {
        Button {
            Task { await stop() }
        } label: {
            ZStack {
                Circle()
                    .fill(.red.opacity(0.15))
                    .scaleEffect(1 + CGFloat(recorder.level) * 0.4)
                Circle()
                    .strokeBorder(.red, lineWidth: 4)
                    .padding(12)
                RoundedRectangle(cornerRadius: 8)
                    .fill(.red)
                    .frame(width: 32, height: 32)
            }
            .frame(width: 100, height: 100)
            .animation(.easeOut(duration: 0.1), value: recorder.level)
        }
        .disabled(recorder.state != .recording)
        .accessibilityLabel("녹음 중지")
    }

    private func start() async {
        do {
            try await recorder.start(locale: Locale(identifier: languageID))
        } catch is CancellationError {
            // 사용자가 취소함
        } catch {
            needsMicrophoneSetting = (error as? Recorder.RecorderError) == .microphoneDenied
            errorMessage = error.localizedDescription
        }
    }

    private func stop() async {
        guard let output = await recorder.stop() else { return }
        let recording = Recording(
            title: Recording.defaultTitle(for: output.startedAt),
            createdAt: output.startedAt,
            duration: output.duration,
            transcript: output.transcript.text,
            audioFileName: output.audioFileName,
            languageID: languageID,
            words: output.transcript.words
        )
        context.insert(recording)
        dismiss()
    }
}
