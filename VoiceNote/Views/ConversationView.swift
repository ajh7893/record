import SpeakerDiarization
import SwiftUI

/// 화자 구분 결과를 대화 형식으로 보여준다.
/// 화자 이름을 눌러 이름을 바꾸거나 다른 화자와 합칠 수 있고, 시간을 누르면 그 부분부터 재생한다.
struct ConversationView: View {
    let recording: Recording
    let player: AudioPlayer
    @State private var renamingSpeaker: Int?
    @State private var nameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(recording.speakerLines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .alert(
            "이름 바꾸기",
            isPresented: Binding(get: { renamingSpeaker != nil }, set: { if !$0 { renamingSpeaker = nil } })
        ) {
            TextField("이름", text: $nameDraft)
            Button("저장") {
                guard let speaker = renamingSpeaker else { return }
                let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                recording.speakerNames[speaker] = name.isEmpty ? nil : name
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 화자가 한 모든 말에 적용돼요.")
        }
    }

    private func row(_ line: SpeakerLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                speakerMenu(for: line.speaker)
                Button {
                    player.seek(to: line.start)
                    player.play()
                } label: {
                    Label(line.start.clockText, systemImage: "play.fill")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(line.start.clockText)부터 재생")
            }
            Text(line.text)
                .textSelection(.enabled)
        }
    }

    private func speakerMenu(for speaker: Int) -> some View {
        Menu {
            Button("이름 바꾸기", systemImage: "pencil") {
                nameDraft = recording.speakerNames[speaker] ?? ""
                renamingSpeaker = speaker
            }
            let others = recording.speakers.filter { $0 != speaker }
            if !others.isEmpty {
                Menu("다른 화자와 합치기") {
                    ForEach(others, id: \.self) { other in
                        Button(recording.speakerName(other)) {
                            recording.mergeSpeaker(speaker, into: other)
                        }
                    }
                }
            }
        } label: {
            Text(recording.speakerName(speaker))
                .font(.subheadline.weight(.semibold))
        }
        .tint(Self.color(for: speaker))
    }

    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal]

    static func color(for speaker: Int) -> Color {
        palette[speaker % palette.count]
    }
}
