//
//  LiveRecorder.swift
//  Live
//
//  Created by wotjd on 2018. 9. 14..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import RTMP
import Capture

class LiveRecorder: NSObject {
    fileprivate let recorderQueue = DispatchQueue(label: "LiveRecorderQueue")
    fileprivate var isRecoding = false
    fileprivate let captureSession = AVCaptureSession()
    fileprivate let videoCapture = VideoCapture()
    fileprivate let audioCapture = AudioCapture()
    fileprivate let videoEncoder = AVCEncoder()
    fileprivate let audioEncoder = AACEncoder()
    fileprivate let muxer = AVWriter(true)
//    fileprivate var muxer = RTMPMuxer()
//    fileprivate var rtmpPublisher = RTMPPublishClient()
    
    public var previewLayer: AVCaptureVideoPreviewLayer {
        return videoCapture.previewLayer
    }
    
    fileprivate var videoOrientation = AVCaptureVideoOrientation.portrait {
        didSet {
            if videoOrientation != oldValue {
                videoCapture.videoOrientation = videoOrientation
                videoEncoder.videoOrientation = videoOrientation
            }
        }
    }
    public var videoEncoderSettings: [String: Any] {
        get {
            return videoEncoder.dictionaryWithValues(forKeys: AVCEncoder.supportedSettingsKeys)
        }
        set {
            videoEncoder.setValuesForKeys(newValue)
        }
    }
    public var audioEncoderSettings: [String: Any] {
        get {
            return audioEncoder.dictionaryWithValues(forKeys: AACEncoder.supportedSettingsKeys)
        }
        set {
            audioEncoder.setValuesForKeys(newValue)
        }
    }
    
    public override init() {
        super.init()
//        setupRTMP()
        setupCapture()
        setupEncode()
//        startSession()    // moved view will appear
    }
    
    public func startSession() {
        recorderQueue.async {
            self.captureSession.startRunning()
            print("session started")
        }
    }
    
    public func stopSession() {
        recorderQueue.async {
            self.captureSession.stopRunning()
            print("session stopped")
        }
    }
    
    func getTempPath() -> URL? {
        let directory = NSTemporaryDirectory() as NSString
        
        guard directory != "" else {
            return nil
        }
        
        let path = directory.appendingPathComponent(NSUUID().uuidString + ".mp4")
        print("\(path)")
        
        return URL(fileURLWithPath: path)
    }
    
    public func startRecord(/*toUrl rtmpUrl: String*/) {
        if isRecoding { return }
        recorderQueue.async {
//            self.captureSession.startRunning()
//            self.rtmpPublisher.setMediaMetaData(self.audioEncoder.metaData)
//            self.rtmpPublisher.setMediaMetaData(self.videoEncoder.metaData)
//            self.rtmpPublisher.connect(rtmpUrl: rtmpUrl)
            self.videoEncoder.run()
            self.audioEncoder.run()
            
            self.muxer.startWriter(self.getTempPath())
            
            self.isRecoding = true
        }
    }
    
    public func stopRecord() {
        guard isRecoding else { return }
        recorderQueue.async {
            //            self.captureSession.stopRunning()
            self.videoEncoder.stop()
            self.audioEncoder.stop()
            //            self.rtmpPublisher.stop()
            
            self.muxer.stopWriter { url in
                print("writing has done : \(url)")
                PHPhotoLibrary.shared().performChanges({ () -> Void in
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { (isSuccess, error) in
                    print("saving video has done")
                }
            }
            
            self.isRecoding = false
        }
    }
    
//    private func setupRTMP() {
//        rtmpPublisher.delegate = self
//        muxer.delegate = self
//    }
    
    private func setupCapture() {
        listenOrientationDidChangeNotification()
        
        audioCapture.session = captureSession
        audioCapture.output { (sampleBuffer) in
            self.handleAudioCaptureBuffer(sampleBuffer)
        }
        audioCapture.attachMicrophone()
        
        videoCapture.session = captureSession
        videoCapture.output { (sampleBuffer) in
            self.handleVideoCaptureBuffer(sampleBuffer)
        }
        videoCapture.attachCamera()
    }
    
    private func setupEncode() {
        audioEncoder.delegate = self
        videoEncoder.delegate = self
    }
    
    private func handleAudioCaptureBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecoding else { return }
        
//        print("got audio capture buffer")
        audioEncoder.encode(sampleBuffer: sampleBuffer)
    }
    
    private func handleVideoCaptureBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecoding else { return }
        
//        print("got video capture buffer")
        videoEncoder.encode(sampleBuffer: sampleBuffer)
    }
}

//extension LiveRecorder: RTMPPublisherDelegate {
//    func publishStreamHasDone() {
//        isRecoding = true
//    }
//}

extension LiveRecorder: AVCEncoderDelegate {
    func didGetAVCFormatDescription(_ formatDescription: CMFormatDescription?) {
        print("got video format description")
        self.muxer.addVideoInput(formatDescription)
//        muxer.muxAVCFormatDescription(formatDescription: formatDescription)
    }
    
    func didGetAVCSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        print("got H264 SampleBuffer")
        self.muxer.appendBuffer(sampleBuffer, isVideo: true)
//        muxer.muxAVCSampleBuffer(sampleBuffer: sampleBuffer)
    }
}

extension LiveRecorder: AACEncoderDelegate {
    func didGetAACFormatDescription(_ formatDescription: CMFormatDescription?) {
        print("got audio format description")
        muxer.addAudioInput(formatDescription)
//        muxer.muxAACFormatDescription(formatDescription: formatDescription)
    }
    
    func didGetAACSampleBuffer(_ sampleBuffer: CMSampleBuffer?) {
        print("got AAC SampleBuffer")
        self.muxer.appendBuffer(sampleBuffer!, isVideo: false)
//        muxer.muxAACSampleBuffer(sampleBuffer: sampleBuffer)
    }
}

//extension LiveRecorder: RTMPMuxerDelegate {
//    func sampleOutput(audio buffer: Data, timestamp: Double) {
//        rtmpPublisher.publishAudio([UInt8](buffer), timestamp: UInt32(timestamp))
//    }
//
//    func sampleOutput(video buffer: Data, timestamp: Double) {
//        rtmpPublisher.publishVideo([UInt8](buffer), timestamp: UInt32(timestamp))
//    }
//}

extension LiveRecorder {
    fileprivate func listenOrientationDidChangeNotification() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIDeviceOrientationDidChange, object: nil, queue: OperationQueue.main) { (notification) in
            var deviceOrientation = UIDeviceOrientation.unknown
            if let device = notification.object as? UIDevice {
                deviceOrientation = device.orientation
            }
            
            func getAVCaptureVideoOrientation(_ orientaion: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
                switch orientaion {
                case .portrait:
                    return .portrait
                case .portraitUpsideDown:
                    return .portraitUpsideDown
                case .landscapeLeft:
                    return .landscapeRight
                case .landscapeRight:
                    return .landscapeLeft
                default:
                    return nil
                }
            }
            
            if let orientation = getAVCaptureVideoOrientation(deviceOrientation), orientation != self.videoOrientation {
                self.videoOrientation = orientation
            }
        }
    }
}
