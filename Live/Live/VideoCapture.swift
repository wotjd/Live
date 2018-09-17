//
//  VideoCapture.swift
//  Capture
//
//  Created by wotjd on 2018. 9. 14..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import AVFoundation

final class VideoCapture: NSObject {
    fileprivate let captureQueue = DispatchQueue(label: "VideoCapture")
    
    var previewLayer : AVCaptureVideoPreviewLayer!
    
    
    /// AudioCapture 와 동일한 세션
    var session: AVCaptureSession?
    fileprivate var captureOutput: AVCaptureVideoDataOutput?
    fileprivate var captureInput: AVCaptureDeviceInput?
    
    fileprivate var outputHandler: OutputHandler?

    var videoOrientation = AVCaptureVideoOrientation.portrait {
        didSet {
            if videoOrientation != oldValue {
                configureVideoOrientation()
            }
        }
    }
    
    // MARK: - Configurations
    
    fileprivate func configureVideoOrientation() {
        if let output = captureOutput, let connection = output.connection(with: AVMediaType.video), connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }
    }
    
    fileprivate func configureVideoPreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session!)
    }
    
    fileprivate func configureCaptureOutput() {
        guard let session = self.session else { return }
        if let captureOutput = self.captureOutput {
            session.removeOutput(captureOutput)
        }
        
        captureOutput = AVCaptureVideoDataOutput()
        captureOutput!.alwaysDiscardsLateVideoFrames = true
        captureOutput!.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        captureOutput!.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(captureOutput!) {
            session.addOutput(captureOutput!)
        }
        
        for connection in captureOutput!.connections {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = videoOrientation
            }
        }
    }
    
    fileprivate func configureCaptureInput() {
        guard let session = self.session else { return }
        if let captureInput = self.captureInput {
            session.removeInput(captureInput)
        }
        
        do {
            let device = AVCaptureDevice.default(for: AVMediaType.video)
            captureInput = try AVCaptureDeviceInput(device: device!)
            if session.canAddInput(captureInput!) {
                session.addInput(captureInput!)
            }
        } catch {
            print("Video Capture Input Error: \(error)")
        }
    }
    
    fileprivate func configureSession() {
        guard let session = self.session else { return }
        session.beginConfiguration()
        if session.canSetSessionPreset(AVCaptureSession.Preset.hd1280x720) {
            session.sessionPreset = AVCaptureSession.Preset.hd1280x720
        }
        session.commitConfiguration()
    }
    
    // MARK: - Methods
    
    func attachCamera() {
        configureCaptureOutput()
        configureCaptureInput()
        configureSession()
        configureVideoOrientation()
        configureVideoPreview()
    }
    
    func output(outputHandler: @escaping OutputHandler) {
        self.outputHandler = outputHandler
    }
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    typealias OutputHandler = (_ sampleBuffer: CMSampleBuffer) -> Void
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        self.outputHandler?(sampleBuffer) // 인코딩되지 않은 데이터 (yuv)
    }
}
