//
//  AVCEncoder.swift
//  Capture
//
//  Created by wotjd on 2018. 9. 14..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import VideoToolbox
import AVFoundation

protocol AVCEncoderDelegate: class {
    func didGetAVCFormatDescription(_ formatDescription: CMFormatDescription?)
    func didGetAVCSampleBuffer(_ sampleBuffer: CMSampleBuffer)
}

final class AVCEncoder: NSObject {
    static let supportedSettingsKeys = [
        "width",
        "height",
        "fps",
        "bitrate",
        "keyFrameIntervalDuration",
    ]
    fileprivate var encoderQueue = DispatchQueue(label: "AVCEncoderQueue")
    var metaData: [String : Any] {
        var metaData = [String : Any]()
        metaData["duration"] = keyFrameIntervalDuration // not sure
        metaData["width"] = width
        metaData["height"] = height
        metaData["videodatarate"] = bitrate//bitrate
        metaData["framerate"] = fps // fps
        metaData["videocodecid"] = 7// avc is 7
        return metaData
    }
    
    /* encoder session rely on width and height ,when it changed we must regenerate the session */
    var width: Int32 = 1280 {
        didSet {
            if self.width != oldValue {
                encoderQueue.async {
                    if self.session != nil { self.configureSession() }
                }
            }
        }
    }
    
    var height: Int32 = 720 {
        didSet {
            if self.height == oldValue {
                encoderQueue.async {
                    if self.session != nil { self.configureSession() }
                }
            }
        }
    }
    
    var videoOrientation = AVCaptureVideoOrientation.portrait {
        didSet {
            if self.videoOrientation != oldValue {
                (self.width, self.height) = (self.height, self.width)
            }
        }
    }
    
    var fps: Float64 = 25 {
        didSet {
            if self.fps != oldValue {
                encoderQueue.async {
                    if let session = self.session {
                        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameInterval, self.fps as CFTypeRef)
                        VTSessionSetProperty(session, kVTCompressionPropertyKey_ExpectedFrameRate, self.fps as CFTypeRef)
                    }
                }
            }
        }
    }
    
    /// @see about bitrate: https://ko.wikipedia.org/wiki/비트레이트
    var bitrate: UInt32 = 200 * 1000 {
        didSet {
            if self.bitrate != oldValue {
                encoderQueue.async {
                    if let session = self.session {
                        VTSessionSetProperty(session, kVTCompressionPropertyKey_AverageBitRate, CFNumberCreate(nil, .sInt32Type, &self.bitrate))
                    }
                }
            }
        }
    }
    
    var keyFrameIntervalDuration: Double = 2.0 {
        didSet {
            if self.keyFrameIntervalDuration != oldValue {
                encoderQueue.async {
                    if let session = self.session {
                        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, CFNumberCreate(nil, .doubleType, &self.keyFrameIntervalDuration))
                    }
                }
            }
        }
    }
    
    weak var delegate: AVCEncoderDelegate?
    
    fileprivate var session: VTCompressionSession?
    fileprivate var formatDescription: CMFormatDescription?
    
    /// 인코딩 성공 콜백
    fileprivate var callback: VTCompressionOutputCallback = {(
        outputCallbackRefCon:UnsafeMutableRawPointer?,
        sourceFrameRefCon:UnsafeMutableRawPointer?,
        status:OSStatus,
        infoFlags:VTEncodeInfoFlags,
        sampleBuffer:CMSampleBuffer?
        ) in
        // 인코딩 된 데이터
        guard let sampleBuffer = sampleBuffer, status == noErr, infoFlags != .frameDropped else { return }
        let encoder = unsafeBitCast(outputCallbackRefCon, to: AVCEncoder.self)
        let isKeyFrame = !CFDictionaryContainsKey(unsafeBitCast(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0), to: CFDictionary.self), unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self))
        if isKeyFrame {
            let description = CMSampleBufferGetFormatDescription(sampleBuffer)
            if !CMFormatDescriptionEqual(description, encoder.formatDescription) {
                encoder.delegate?.didGetAVCFormatDescription(description)
                encoder.formatDescription = description
            }
        }
        encoder.delegate?.didGetAVCSampleBuffer(sampleBuffer)
    }
    
    fileprivate func configureSession() {
        if let session = self.session {
            VTCompressionSessionInvalidate(session)
            self.session = nil
        }
        let attributes: [NSString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferOpenGLESCompatibilityKey: true,
            kCVPixelBufferHeightKey: NSNumber(value: height),
            kCVPixelBufferWidthKey: NSNumber(value: width),
        ]
        let _ = VTCompressionSessionCreate(kCFAllocatorDefault, height, width, kCMVideoCodecType_H264, nil, attributes as CFDictionary?, nil, callback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self), &session) // 너비와 높이 설정이 바뀌고 비디오의 중간 부분 만 보입니다.
        
        let profileLevel = kVTProfileLevel_H264_Baseline_3_1 as String
        let isBaseline = profileLevel.contains("Baseline")
        
        var properties: [NSString: Any] = [
            kVTCompressionPropertyKey_RealTime: kCFBooleanTrue,
            kVTCompressionPropertyKey_ProfileLevel: profileLevel,
            kVTCompressionPropertyKey_AverageBitRate: Int(bitrate), // 평균 비트 전송률（bps）
            kVTCompressionPropertyKey_ExpectedFrameRate: NSNumber(value: fps), // 예상 프레임 레이트
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: NSNumber(value: keyFrameIntervalDuration), // 키 프레임（GOPsize） 간격
            kVTCompressionPropertyKey_AllowFrameReordering: !isBaseline,
            kVTCompressionPropertyKey_PixelTransferProperties: [
                "ScalingMode": "Trim"]
        ]
        if !isBaseline {
            properties[kVTCompressionPropertyKey_H264EntropyMode] = kVTH264EntropyMode_CABAC
        }
        if session != nil {
            VTSessionSetProperties(session!, properties as CFDictionary)
        }
    }
    
    fileprivate func enableSession() {
        guard let session = session else { return }
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    fileprivate func disableSession() {
        if let session = self.session {
            VTCompressionSessionInvalidate(session)
        }
        self.session = nil
        formatDescription = nil // nil 로 설정돼야함. 안하면 다시할 때 sps, pps가 전송되지 않으며 일부 서버에서는 재생되지 않음
    }
    
    func encode(sampleBuffer: CMSampleBuffer) {
        guard let session = self.session else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        var flags = VTEncodeInfoFlags()
        VTCompressionSessionEncodeFrame(session, imageBuffer, presentationTimestamp, duration, nil, nil, &flags)
    }
    
    func run() {
        configureSession()
        enableSession()
    }
    
    func stop() {
        disableSession()
    }
}
