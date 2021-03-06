//
//  LiveRecorder.swift
//  Live
//
//  Created by wotjd on 2018. 8. 31..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import AVFoundation
//import AssetsLibrary

class AVWriter : NSObject {
    private var assetWriter: AVAssetWriter!
    private var videoInputWriter: AVAssetWriterInput!
    private var audioInputWriter: AVAssetWriterInput!
    private var isFirstFrame = true
    private var startTime : CMTime!
    private var endTime : CMTime!
    private var isStarted = false
    private let asEncoder = false
    private let isAudioMuted : Bool
    
    init(_ muteAudio: Bool) {
        self.isAudioMuted = muteAudio
        super.init()
    }
    
    func getVideoOutputSettings() -> Dictionary<String, AnyObject>? {
        if asEncoder {
            let width = 1920, height = 1080
            return [
                AVVideoCodecKey : AVVideoCodecType.h264 as AnyObject,
                AVVideoWidthKey : width as AnyObject,
                AVVideoHeightKey : height as AnyObject
            ]
        } else {
            print("video output settings : nil")
            return nil  // passthrough
        }
    }
    
    func getAudioOutputSettings() -> Dictionary<String, AnyObject>? {
        if asEncoder {
            let samples = 44100, channels = 1
            return [
                AVFormatIDKey : Int(kAudioFormatMPEG4AAC) as AnyObject,
                AVNumberOfChannelsKey : channels as AnyObject,
                AVSampleRateKey : samples as AnyObject,
                AVEncoderBitRateKey : 128000 as AnyObject
            ]
        } else {
            print("audio output settings : nil")
            return nil  // passthrough
        }
    }
    
    func initAVWriter(_ url:URL!) {
        self.assetWriter = try? AVAssetWriter(outputURL: url, fileType: AVFileType.mov)
    }
    
    func addVideoInput(_ formatDescription : CMFormatDescription?) {
        guard videoInputWriter == nil && self.isStarted else {
            print("videoInputWriter has already set")
            return
        }
        let videoOutputSettings: Dictionary<String, AnyObject>? = self.getVideoOutputSettings()
        
        self.videoInputWriter = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoOutputSettings, sourceFormatHint: formatDescription)
        
        self.videoInputWriter.expectsMediaDataInRealTime = true
        
        if self.assetWriter.canAdd(self.videoInputWriter) {
            assetWriter.add(videoInputWriter)
        }
    }
    
    func addAudioInput(_ formatDescription : CMFormatDescription?) {
        guard isAudioMuted == false && audioInputWriter == nil && self.isStarted else {
            print("audioInputWriter has already set")
            return
        }
//        var format = ""
//        format += "\(CMFormatDescriptionGetMediaType(formatDescription!).description)/"
//        format += "\(CMFormatDescriptionGetMediaSubType(formatDescription!).description)"
//        print("addAudioInput: \(format)")
        // => 1936684398/1819304813 == to ASCII (soun/lpcm) == kCMMediaType_Audio/kAudioFormatLinearPCM
        // => 1936684398/1633772320 == to ASCII (soun/aac) == kCMMediaType_Audio/kAudioFormatMPEG4AAC
        let audioOutputSettings: Dictionary<String, AnyObject>? = self.getAudioOutputSettings()
        
        self.audioInputWriter = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettings, sourceFormatHint: formatDescription) //
        
        self.audioInputWriter.expectsMediaDataInRealTime = true
        
        if self.assetWriter.canAdd(self.audioInputWriter) {
            assetWriter.add(audioInputWriter)
        }
    }
    
    func startWriter(_ url:URL!) {
        guard !self.isStarted else {
            print("writer already started!")
            return
        }
        self.isFirstFrame = true
        //        self.startTime = CMClockGetTime(CMClockGetHostTimeClock())
        self.initAVWriter(url)
        self.isStarted = true
    }
    
    func stopWriter(_ callback: @escaping (_ url: URL) -> Void) {
        guard self.isStarted else {
            print("[AVWriter] stopWriter : writer not started!")
            return
        }
        self.videoInputWriter.markAsFinished()
        if !self.isAudioMuted {
            self.audioInputWriter.markAsFinished()
        }
        
        self.assetWriter.endSession(atSourceTime: endTime)
        
        self.assetWriter.finishWriting {
            self.videoInputWriter = nil
            self.audioInputWriter = nil
            
            callback(self.assetWriter.outputURL)
            
            self.assetWriter = nil
            self.isStarted = false
        }
        /*
         self.assetWriter.finishWriting { () -> Void in
         if let blockCompletion = blockCompletion {
         blockCompletion(self.assetWriter.outputURL, nil)
         }
         }*/
    }
    
    func appendBuffer(_ sampleBuffer: CMSampleBuffer, isVideo: Bool) {
        guard self.isStarted else {
            print("[AVWriter] appendBuffer : writer not started!")
            return
        }
        
        if !isVideo && self.isFirstFrame {
            print("ignoring audio frame before first video frame..")
        } else if CMSampleBufferDataIsReady(sampleBuffer) {
            if self.assetWriter.status == AVAssetWriterStatus.unknown {
                print("Start writing, isVideo = \(isVideo), status = \(self.assetWriter.status.rawValue)")
                self.startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.assetWriter.startWriting()
                self.assetWriter.startSession(atSourceTime: startTime)
                self.isFirstFrame = false
            }
            
            if self.assetWriter.status == AVAssetWriterStatus.failed {
                print("Error occured, isVideo = \(isVideo), status = \(self.assetWriter.status.rawValue), \(self.assetWriter.error!.localizedDescription)")
                return
            }
            
            if isVideo {
                if self.videoInputWriter.isReadyForMoreMediaData {
                    self.videoInputWriter.append(sampleBuffer)
                }
            } else if !self.isAudioMuted {
                if self.audioInputWriter.isReadyForMoreMediaData {
                    self.audioInputWriter.append(sampleBuffer)
                }
            }
            endTime = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), startTime)
        }
    }
}
