// swift-tools-version: 6.2
import PackageDescription

// 보이스노트의 화자 구분 기능. FluidAudio(Apache 2.0)에서 화자 구분 부분만 가져온다.
// (traits: []로 텍스트 정규화 엔진(NemoTextProcessing)을 빼서 앱 용량을 줄인다.)
let package = Package(
    name: "SpeakerDiarization",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SpeakerDiarization", targets: ["SpeakerDiarization"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: [])
    ],
    targets: [
        .target(
            name: "SpeakerDiarization",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        )
    ],
    swiftLanguageModes: [.v5]
)
