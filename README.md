# Live

Live framework for iOS.

### Base Code : [victorchee](https://github.com/victorchee)/**Live** (Github)

#### 기본 제공 기능

1. A/V 캡쳐 (from Camera, Mic)
2. Video - AVC 인코딩, Audio - AAC 인코딩
3. RTMP 스트리밍

#### 수정 및 추가 내역

1. VideoPreview 에 뭔가 문제가 있어 Apple 기본 제공 Layer (AVCaptureVideoPreviewLayer) 로 변경 
2. RTMP 스트리밍용 클래스 삭제, LiveRecording 클래스 추가
3. AVWrtier 추가 (from wotjdCam), 기능연동은 아직 안됨
   - 기존 AVWriter 코드에서 addAudioInput, addVideoInput 호출 부분 제거 

1. AVWriter 수정

- startWriter, stopWriter 에 초기화 코드 추가
  - 초기화 대상 : assetWriter (AVAssetWriter), videoInputWriter (AVAssetWriterInput), audioInputWriter (AVAssetWriterInput)

1. AVWriter 기능 연동

- LiveRecoder 클래스
  - startWriter, stopWriter 코드 추가
  - extension : AVCEncoderDelegate
    - didGetAVCFormatDescription 메소드에 addVideoInput 호출 코드 추가
    - didGetAVCSampleBuffer 메소드에 appendBuffer(isVideo true) 호출 코드 추가 (Mux H.264 Encoded data)
  - extension : AACEncoderDelegate
    - didGetAACFormatDescription 메소드에 addVideoInput 호출 코드 추가
    - didGetAACSampleBuffer 메소드에 appendBuffer(isVideo false) 코드 추가 (Mux AAC Encoded data)

#### 참고자료

https://stackoverflow.com/questions/18728584/do-viewwilldisappear-viewdiddisappear-get-called-when-switching-apps
