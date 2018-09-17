//
//  AACEncoder.swift
//  Capture
//
//  Created by wotjd on 2018. 9. 14..
//  Copyright © 2018년 wotjd. All rights reserved.
//

/**
 - seealso:
 - https://developer.apple.com/library/ios/technotes/tn2236/_index.html
 - https://developer.apple.com/library/ios/documentation/AudioVideo/Conceptual/MultimediaPG/UsingAudio/UsingAudio.html
 */

import Foundation
import AVFoundation

protocol AACEncoderDelegate: class {
    func didGetAACFormatDescription(_ formatDescription: CMFormatDescription?)
    func didGetAACSampleBuffer(_ sampleBuffer: CMSampleBuffer?)
}

final class AACEncoder: NSObject {
    fileprivate let aacEncoderQueue = DispatchQueue(label: "AACEncoder")
    fileprivate var isRunning = false
    weak var delegate: AACEncoderDelegate?
    static let supportedSettingsKeys = [
        "muted",
        "bitrate",
        "profile",
        "sampleRate", // not available yet
    ]
    var metaData: [String: Any] {
        var metaData = [String: Any]()
        metaData["audiodatarate"] = bitrate
        metaData["audiosamplerate"] = 44100 // audio sample rate
        metaData["audiosamplesize"] = 16
        metaData["stereo"] = false // 스테레오 (듀얼 채널)
        metaData["audiocodecid"] = 10
        return metaData
    }
    var muted = false
    var bitrate: UInt32 = 32*1024 {
        didSet {
            aacEncoderQueue.async {
                guard let converter = self._converter else { return }
                var bitrate: UInt32 = self.bitrate * self.inDestinationFormat.mChannelsPerFrame
                AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &bitrate)
            }
        }
    }
    fileprivate var profile = UInt32(MPEG4ObjectID.AAC_LC.rawValue)
    /// 오디오 설명 정보를 위한 AAC 관련 패키지 변환
    fileprivate var formatDescription: CMFormatDescription? {
        didSet {
            if !CMFormatDescriptionEqual(formatDescription, oldValue) {
                delegate?.didGetAACFormatDescription(formatDescription)
            }
        }
    }
    
    fileprivate var currentBufferList: UnsafeMutableAudioBufferListPointer? = nil
    fileprivate var maximumBuffers = 1
    fileprivate var bufferListSize = AudioBufferList.sizeInBytes(maximumBuffers: 1)
    // 입력 오디오 포맷 (PCM 데이터 정보)
    fileprivate var inSourceFormat: AudioStreamBasicDescription? {
        didSet {
            guard let inSourceFormat = self.inSourceFormat else { return }
            let nonInterleaved = inSourceFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            if nonInterleaved {
                maximumBuffers = Int(inSourceFormat.mChannelsPerFrame)
                bufferListSize = AudioBufferList.sizeInBytes(maximumBuffers: maximumBuffers)
            }
        }
    }
    fileprivate var inputDataProc: AudioConverterComplexInputDataProc = {(
        converter: AudioConverterRef,
        ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
        ioData: UnsafeMutablePointer<AudioBufferList>,
        outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
        inUserData: UnsafeMutableRawPointer?) in
        return unsafeBitCast(inUserData, to: AACEncoder.self).onInputDataForAudioConverter(ioNumberDataPackets: ioNumberDataPackets, ioData: ioData, outDataPacketDescription: outDataPacketDescription)
    }
    
    /// 출력 오디오 형식
    fileprivate var _inDestinationFormat: AudioStreamBasicDescription?
    fileprivate var inDestinationFormat: AudioStreamBasicDescription {
        get {
            if self._inDestinationFormat == nil {
                self._inDestinationFormat = AudioStreamBasicDescription(
                    mSampleRate: inSourceFormat!.mSampleRate,// 샘플레이트 44100
                    mFormatID: kAudioFormatMPEG4AAC, // 압축 인코딩 형식 MPEG4-AAC
                    mFormatFlags: UInt32(MPEG4ObjectID.aac_Main.rawValue),
                    mBytesPerPacket: 0,
                    mFramesPerPacket: 1024, // AAC 프레임의 크기는 기본값이 1024Bytes
                    mBytesPerFrame: 0, //
                    mChannelsPerFrame: inSourceFormat!.mChannelsPerFrame, // 샘플링 채널 수， ipad4 is 1
                    mBitsPerChannel: 0, // 샘플 수 일 수도 있습니다.
                    mReserved: 0)//  Pads the structure out to force an even 8-byte alignment. Must be set to 0.
                
                CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &self._inDestinationFormat!, 0, nil, 0, nil, nil, &formatDescription) // formatDescription 값 설정
            }
            return self._inDestinationFormat!
        }
        set {
            self._inDestinationFormat = newValue
        }
    }
    fileprivate var inClassDescriptions: [AudioClassDescription] = [
        AudioClassDescription(mType: kAudioEncoderComponentType, mSubType: kAudioFormatMPEG4AAC, mManufacturer: kAppleSoftwareAudioCodecManufacturer),
        AudioClassDescription(mType: kAudioEncoderComponentType, mSubType: kAudioFormatMPEG4AAC, mManufacturer: kAppleHardwareAudioCodecManufacturer)
    ]
    
    /// AudioConverter 에 대한 데이터 콜백
    private func onInputDataForAudioConverter(ioNumberDataPackets: UnsafeMutablePointer<UInt32>, ioData: UnsafeMutablePointer<AudioBufferList>, outDataPacketDescription:UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> OSStatus {
        guard let bufferList = currentBufferList else {
            ioNumberDataPackets.pointee = 0
            return -1
        }
        memcpy(ioData, bufferList.unsafePointer, bufferListSize)
        ioNumberDataPackets.pointee = 1
        free(bufferList.unsafeMutablePointer)
        currentBufferList = nil
        return noErr
    }
    
    fileprivate var _converter: AudioConverterRef?
    fileprivate var converter: AudioConverterRef {
        if self._converter == nil {
            var converter: AudioConverterRef? = nil
            let status = AudioConverterNewSpecific(&self.inSourceFormat!, &self.inDestinationFormat, UInt32(self.inClassDescriptions.count), &inClassDescriptions, &converter)
            if status == noErr {
                var bitrate: UInt32 = self.bitrate*self.inDestinationFormat.mChannelsPerFrame
                AudioConverterSetProperty(converter!, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &bitrate) // 코드 출력 비트 전송률 설정 32kbps
            }
            self._converter = converter
        }
        return self._converter!
    }
    
    private func createAudioBufferList(channels: UInt32, size: UInt32) -> AudioBufferList {
        let audioBuffer = AudioBuffer(mNumberChannels: channels, mDataByteSize: size, mData: UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<UInt32>.size(ofValue: size), alignment: MemoryLayout<UInt32>.alignment(ofValue: size)))
        return AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
    }
    
    func encode(sampleBuffer: CMSampleBuffer) {
        guard isRunning, let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        if inSourceFormat == nil {
            inSourceFormat = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee // PCM 정보
        }
        
        var blockBuffer: CMBlockBuffer?
        currentBufferList = AudioBufferList.allocate(maximumBuffers: maximumBuffers)
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, nil, currentBufferList!.unsafeMutablePointer, bufferListSize, nil, nil, 0, &blockBuffer)
        
        if muted {
            for buffer in currentBufferList! {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
        }
        
        var ioOutputDataPacketSize: UInt32 = 1
        let dataLength = CMBlockBufferGetDataLength(blockBuffer!)
        let outputData = AudioBufferList.allocate(maximumBuffers: 1)
        outputData[0].mNumberChannels = inDestinationFormat.mChannelsPerFrame
        outputData[0].mDataByteSize = UInt32(dataLength)
        outputData[0].mData = malloc(dataLength)
        
        let status = AudioConverterFillComplexBuffer(converter, inputDataProc, unsafeBitCast(self, to: UnsafeMutableRawPointer.self), &ioOutputDataPacketSize, outputData.unsafeMutablePointer, nil) // Fill this output buffer with encoded data from the encoder
        if status == noErr {
            var outputBuffer: CMSampleBuffer?
            var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sampleBuffer), presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer), decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer))
            let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
            CMSampleBufferCreate(kCFAllocatorDefault, nil, false, nil, nil, formatDescription, numSamples, 1, &timing, 0, nil, &outputBuffer)
            CMSampleBufferSetDataBufferFromAudioBufferList(outputBuffer!, kCFAllocatorDefault, kCFAllocatorDefault, 0, outputData.unsafePointer)
            // 인코딩 후 오디오 패키지 출력
            delegate?.didGetAACSampleBuffer(outputBuffer) // 인코딩된 데이터
        }
        
        for buffer in outputData {
            free(buffer.mData)
        }
        free(outputData.unsafeMutablePointer)
    }
    
    func run() {
        aacEncoderQueue.async {
            self.isRunning = true
        }
    }
    
    func stop() {
        aacEncoderQueue.async {
            if self._converter != nil {
                AudioConverterDispose(self._converter!)
                self._converter = nil
            }
            self.inSourceFormat = nil
            self.formatDescription = nil
            self._inDestinationFormat = nil
            self.currentBufferList = nil
            self.isRunning = false
        }
    }
}
