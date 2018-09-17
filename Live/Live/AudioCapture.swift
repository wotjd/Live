//
//  AudioCapture.swift
//  Capture
//
//  Created by wotjd on 2018. 9. 14..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import AVFoundation

final class AudioCapture: NSObject {
    fileprivate let captureQueue = DispatchQueue(label: "AudioCaptureQueue")
    
    /// VideoCapture 와 동일한 세션
    var session: AVCaptureSession?
    fileprivate var captureOutput: AVCaptureAudioDataOutput?
    fileprivate var captureInput: AVCaptureDeviceInput?
    
    fileprivate var outputHandler: OutputHandler?
    
    // MARK: - Configurations
    
    fileprivate func configureCaptureOutput() {
        guard let session = self.session else { return }
        if let captureOutput = self.captureOutput {
            captureOutput.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(captureOutput)
        }
        
        captureOutput = AVCaptureAudioDataOutput()
        captureOutput!.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(captureOutput!) {
            session.addOutput(captureOutput!)
        }
    }
    
    fileprivate func configureCaptureInput() {
        guard let session = self.session else { return }
        if let captureInput = self.captureInput {
            session.removeInput(captureInput)
        }
        
        do {
            let device = AVCaptureDevice.default(for: AVMediaType.audio)
            captureInput = try AVCaptureDeviceInput(device: device!)
            if session.canAddInput(captureInput!) {
                session.addInput(captureInput!)
            }
        } catch {
            print("Audio Capture Input Error: \(error)")
        }
    }
    
    // MARK: - Methods
    
    func attachMicrophone() {
        configureCaptureOutput()
        configureCaptureInput()
    }
    
    func output(outputHandler: @escaping OutputHandler) {
        self.outputHandler = outputHandler
    }
}

extension AudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    typealias OutputHandler = (_ sampleBuffer: CMSampleBuffer) -> Void
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        self.outputHandler?(sampleBuffer) // 인코딩되지 않은 데이터 (PCM)
    }
}
