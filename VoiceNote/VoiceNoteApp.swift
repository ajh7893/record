import SwiftData
import SwiftUI

@main
struct VoiceNoteApp: App {
    var body: some Scene {
        WindowGroup {
            RecordingListView()
        }
        .modelContainer(for: Recording.self)
    }
}
