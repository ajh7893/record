import SwiftData
import SwiftUI

/// 첫 화면: 녹음 목록과 녹음 시작 버튼
struct RecordingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @AppStorage(TranscriptionLanguage.storageKey) private var languageID = TranscriptionLanguage.defaultID
    @State private var isRecording = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(recordings) { recording in
                    NavigationLink(value: recording) {
                        RecordingRow(recording: recording)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("보이스노트")
            .navigationDestination(for: Recording.self) { recording in
                RecordingDetailView(recording: recording)
            }
            .overlay {
                if recordings.isEmpty {
                    ContentUnavailableView(
                        "아직 녹음이 없어요",
                        systemImage: "waveform",
                        description: Text("아래 버튼을 눌러 녹음을 시작하면\n말하는 내용이 바로 텍스트로 바뀌어요.")
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isRecording = true
                } label: {
                    Label("녹음 시작", systemImage: "mic.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("인식 언어", selection: $languageID) {
                            ForEach(TranscriptionLanguage.options, id: \.id) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                    } label: {
                        Label("인식 언어", systemImage: "globe")
                    }
                }
            }
            .fullScreenCover(isPresented: $isRecording) {
                RecordView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            recordings[index].deleteWithAudio(in: context)
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(recording.duration.clockText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(recording.transcript.isEmpty ? "인식된 텍스트 없음" : recording.transcript)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RecordingListView()
        .modelContainer(for: Recording.self, inMemory: true)
}
