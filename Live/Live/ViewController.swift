//
//  ViewController.swift
//  Live
//
//  Created by wotjd on 2018. 9. 14..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var recorderSwitch: UISwitch!
    
    let recorder: LiveRecorder = LiveRecorder();
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let previewLayer = self.recorder.previewLayer
        
        previewLayer.frame = cameraView.bounds
        cameraView.layer.addSublayer(previewLayer)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        self.recorder.stopSession()
//        self.recorder.stopRecord()
        self.setRecorderStatus(false)
        self.recorderSwitch.setOn(false, animated: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.recorder.startSession()
    }

    func setRecorderStatus(_ status : Bool) {
        if status {
            statusLabel.text = "Recording..."
            self.recorder.startRecord()
        } else {
            statusLabel.text = "Not Recording"
            self.recorder.stopRecord()
        }
    }
    
    @IBAction func onSwitch(_ sender: UISwitch) {
        self.setRecorderStatus(sender.isOn)
    }
}

