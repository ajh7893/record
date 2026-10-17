import SpeakerDiarization
import SwiftData
import SwiftUI
import UIKit

/// 녹음 상세 화면: 텍스트·대화 보기, 화자 구분, 수정, 복사·공유, 녹음 다시 듣기
struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @State private var player = AudioPlayer()
    @State private var analysis = SpeakerAnalysis()
    @State private var isEditing = false
    @State private var showsConversation = true

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                TextEditor(text: $recording.transcript)
                    .font(.body)
                    .padding(.horizontal)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(recording.createdAt.formatted(date: .long, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        speakerSection
                        if showsConversation && !recording.speakerLines.isEmpty {
                            ConversationView(recording: recording, player: player)
                        } else if recording.transcript.isEmpty {
                            Text("인식된 텍스트가 없어요.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(recording.transcript)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
            PlayerBar(player: player)
        }
        .navigationTitle($recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(isEditing ? "완료" : "편집") {
                    isEditing.toggle()
                }
                Menu {
                    Button("텍스트 복사", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = recording.shareText
                    }
                    ShareLink("텍스트 공유", item: recording.shareText)
                    ShareLink("녹음 파일 공유", item: recording.audioURL)
                    if !recording.speakerLines.isEmpty {
                        Divider()
                        Button("화자 다시 구분", systemImage: "arrow.clockwise") {
                            Task { await analysis.run(for: recording) }
                        }
                        .disabled(analysis.isRunning)
                    }
                } label: {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            player.load(url: recording.audioURL)
        }
        .onDisappear {
            player.stop()
        }
    }

    @ViewBuilder
    private var speakerSection: some View {
        switch analysis.phase {
        case .transcribing:
            progressCard("녹음을 다시 읽는 중…", progress: nil)
        case .preparingModel:
            progressCard("화자 구분 모델 준비 중… (처음 한 번은 내려받아요)", progress: nil)
        case .analyzing(let progress):
            progressCard("목소리를 분석하는 중…", progress: progress)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                Button("다시 시도") {
                    Task { await analysis.run(for: recording) }
                }
            }
            .card()
        case .idle:
            if recording.speakerLines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Task { await analysis.run(for: recording) }
                    } label: {
                        Label("화자 구분하기", systemImage: "person.2")
                    }
                    .buttonStyle(.bordered)
                    Text("누가 어떤 말을 했는지 목소리로 나눠요. 녹음은 아이폰 밖으로 나가지 않아요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("보기", selection: $showsConversation) {
                    Text("대화").tag(true)
                    Text("전체 텍스트").tag(false)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func progressCard(_ title: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
            if let progress {
                ProgressView(value: progress)
            } else {
                ProgressView()
            }
        }
        .card()
    }
}

private extension View {
    func card() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
    }
}

private struct PlayerBar: View {
    let player: AudioPlayer

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                in: 0...max(player.duration, 0.1)
            )
            HStack {
                timeLabel(player.currentTime)
                Spacer()
                Button {
                    player.skip(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                .padding(.horizontal, 24)
                Button {
                    player.skip(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                Spacer()
                timeLabel(player.duration)
            }
        }
        .padding()
        .background(.bar)
    }

    private func timeLabel(_ time: TimeInterval) -> some View {
        Text(time.clockText)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}
