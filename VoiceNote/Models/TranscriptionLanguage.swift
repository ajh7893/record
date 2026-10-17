import Foundation

/// 음성 인식 언어 설정. 선택한 값은 @AppStorage(storageKey)로 저장된다.
enum TranscriptionLanguage {
    static let storageKey = "transcriptionLanguage"
    static let defaultID = "ko-KR"

    static let options: [(id: String, name: String)] = [
        ("ko-KR", "한국어"),
        ("en-US", "English"),
        ("ja-JP", "日本語"),
        ("zh-CN", "中文"),
    ]
}
