# 보이스노트 (VoiceNote)

말하는 내용을 녹음하면서 실시간으로 텍스트로 바꿔 주는 아이폰 앱이에요.

- 녹음하는 동안 말한 내용이 화면에 바로 텍스트로 나타나요
- 음성 인식은 아이폰 안에서 처리돼요 (인터넷·유료 API 필요 없음, 언어 모델을 처음 받을 때만 인터넷 필요)
- 녹음 목록 저장, 다시 듣기(15초 앞뒤 이동), 텍스트 수정·복사·공유, 녹음 파일 공유
- **화자 구분**: 녹음 상세 화면의 "화자 구분하기"를 누르면 누가 어떤 말을 했는지 대화 형식으로 나눠요. 화자 이름 바꾸기, 화자 합치기, 시간을 눌러 그 부분부터 듣기도 돼요. 아이폰 안에서 처리되고, 처음 한 번은 모델(약 22MB)을 내려받아요.
- 화면이 꺼져도 녹음이 계속돼요
- 인식 언어: 한국어(기본), English, 日本語, 中文 (첫 화면 오른쪽 위 🌐 메뉴)

## 필요한 것

- Mac + Xcode 26 이상
- **iOS 26 이상**이 설치된 아이폰 (iPhone 11 이후 모델)
- Apple ID (무료 계정이면 충분해요)

## 내 아이폰에 설치하기 (무료 Apple ID)

1. `VoiceNote.xcodeproj`를 더블클릭해서 Xcode로 열어요.
2. Xcode 메뉴 **Xcode → Settings → Accounts**(버전에 따라 Apple Accounts)에서 **+** 를 눌러 Apple ID를 추가해요.
3. 왼쪽에서 **VoiceNote 프로젝트 → TARGETS: VoiceNote → Signing & Capabilities** 탭을 열고,
   **Team**에서 `(Personal Team)`이 붙은 내 이름을 골라요.
   - "bundle identifier is not available" 오류가 나면 **Bundle Identifier**를
     `com.내영문이름.VoiceNote`처럼 다른 값으로 바꿔요.
4. 아이폰을 USB 케이블로 Mac에 연결하고, 아이폰에 "이 컴퓨터를 신뢰하겠습니까?"가 뜨면 **신뢰**를 눌러요.
5. 아이폰 **설정 → 개인정보 보호 및 보안 → 개발자 모드**를 켜요 (재시동돼요).
   - 이 메뉴는 아이폰을 Xcode에 한 번 연결한 뒤에 나타나요.
6. Xcode 위쪽 가운데 기기 선택 메뉴에서 내 아이폰을 고르고 **▶ (Run)** 버튼을 눌러요.
7. 처음 실행할 때 "신뢰하지 않는 개발자"라고 나오면
   아이폰 **설정 → 일반 → VPN 및 기기 관리**에서 내 Apple ID를 눌러 **신뢰**해요.
8. 앱을 열고 녹음 버튼을 누르면 마이크 권한을 물어봐요. **허용**을 눌러요.
   처음 녹음할 때는 한국어 음성 인식 모델을 내려받느라 잠깐 기다릴 수 있어요.

### 무료 계정의 제약

- 설치한 앱은 **7일 뒤 실행되지 않아요.** 아이폰을 연결하고 Xcode에서 다시 ▶ 를 누르면 돼요 (녹음 데이터는 그대로 남아요).
- 이 방식으로 한 기기에 설치할 수 있는 앱은 최대 3개예요.
- 다른 사람에게 배포(앱스토어, TestFlight)하려면 Apple Developer Program(연 99달러) 가입이 필요해요.

## 앱스토어에 올리고 싶어지면

1. [Apple Developer Program](https://developer.apple.com/programs/)에 가입해요.
2. Signing & Capabilities의 Team을 유료 팀으로 바꿔요.
3. Xcode에서 **Product → Archive** → **Distribute App**으로 App Store Connect에 올려요.
4. App Store Connect에서 스크린샷과 설명, 개인정보 처리방침 URL을 입력하고 심사를 요청해요.

코드는 지금 그대로 쓸 수 있어요.

## 폴더 구조

```
VoiceNote.xcodeproj         Xcode 프로젝트
VoiceNote/
├── VoiceNoteApp.swift      앱 시작점 (SwiftData 저장소 설정)
├── Info.plist              백그라운드 녹음 설정
├── Models/
│   ├── Recording.swift             녹음 데이터 (제목, 길이, 텍스트, 오디오 파일 이름)
│   └── TranscriptionLanguage.swift 인식 언어 목록
├── Services/
│   ├── Recorder.swift        마이크 녹음 → 파일 저장 + 음성 인식기로 전달
│   ├── LiveTranscriber.swift 실시간 음성 → 텍스트 (애플 SpeechAnalyzer), 단어별 시간 기록
│   ├── SpeakerAnalysis.swift 화자 구분 진행 (파일 재인식 → 목소리 분석 → 문장과 맞추기)
│   └── AudioPlayer.swift     녹음 다시 듣기
├── Views/
│   ├── RecordingListView.swift   첫 화면 (녹음 목록)
│   ├── RecordView.swift          녹음 화면 (실시간 텍스트)
│   ├── RecordingDetailView.swift 상세 화면 (재생, 수정, 공유, 화자 구분)
│   └── ConversationView.swift    화자별 대화 보기 (이름 바꾸기, 합치기)
└── Assets.xcassets         앱 아이콘, 강조 색
Packages/SpeakerDiarization 화자 구분 패키지 (FluidAudio, Apache 2.0 기반)
```

녹음 파일은 앱의 `Documents/Recordings` 폴더에 `.m4a`로 저장돼요.
