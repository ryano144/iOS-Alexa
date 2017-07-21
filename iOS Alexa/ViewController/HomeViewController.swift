//
//  HomeViewController.swift
//  iOS Alexa
//
//  Created by Chintan Prajapati on 23/05/16.
//  Copyright © 2016 Chintan. All rights reserved.
//

import UIKit
import AVFoundation

class HomeViewController: UIViewController, AVAudioPlayerDelegate {

    @IBOutlet var recordButton: UIButton!
    @IBOutlet var statusLabel: UILabel!
    
    fileprivate var isRecording = false
    
    fileprivate var simplePCMRecorder: SimplePCMRecorder
    
    fileprivate let tempFilename = "\(NSTemporaryDirectory())avsexample.wav"
    
    fileprivate var player: AVAudioPlayer?
    
    required init?(coder: NSCoder) {
        self.simplePCMRecorder = SimplePCMRecorder(numberBuffers: 1)
        
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        // Have the recorder create a first recording that will get tossed so it starts faster later
        do {
            try self.simplePCMRecorder.setupForRecording(tempFilename, sampleRate:16000, channels:1, bitsPerChannel:16, errorHandler: { (error:NSError) -> Void in
                print(error)
            })
            try self.simplePCMRecorder.startRecording()
            try self.simplePCMRecorder.stopRecording()
            self.simplePCMRecorder = SimplePCMRecorder(numberBuffers: 1)
        } catch _ {
            //CRToastManager.showNotificationWithMessage("Something went wrong during Microphone initialization", completionBlock: nil)
        }
    }

    @IBAction func recordAction(_ sender: AnyObject) {
        if !self.isRecording {
            do {
                self.isRecording = true
                
                self.simplePCMRecorder = SimplePCMRecorder(numberBuffers: 1)
                try! self.simplePCMRecorder.setupForRecording(tempFilename, sampleRate:16000, channels:1, bitsPerChannel:16, errorHandler: { (error:NSError) -> Void in
                    print(error)
                    try! self.simplePCMRecorder.stopRecording()
                })
                try self.simplePCMRecorder.startRecording()
                
                self.recordButton.setImage(UIImage(named: "StopIcon"), for: UIControlState())
                self.statusLabel.text = "Listening..."
            } catch _ {
                self.statusLabel.text = "Something went wrong while starting Microphone"
            }
        } else {
            
            do {
                self.isRecording = false
            
                self.recordButton.isEnabled = false
            
                try self.simplePCMRecorder.stopRecording()
            
                self.recordButton.setImage(UIImage(named: "MicIcon"), for: UIControlState())
                self.statusLabel.text = "Uploading recording"
            
                self.upload()
            } catch _ {
                self.statusLabel.text = "Something went wrong while stopping Microphone"
            }
        }
        
    }
    
    fileprivate func upload() {
        let uploader = AVSUploader()
        
        uploader.authToken = ISSharedData.sharedInstance.accessToken
        
        uploader.jsonData = self.createMeatadata()
        
        uploader.audioData = try! Data(contentsOf: URL(fileURLWithPath: tempFilename))
        
        uploader.errorHandler = { (error:NSError) in
            if Config.Debug.Errors {
                print("Upload error: \(error)")
            }
            
            DispatchQueue.main.async(execute: { () -> Void in
                self.statusLabel.text = "Upload error: \(error.localizedDescription)"
                self.recordButton.isEnabled = true
            })
        }
        
        uploader.progressHandler = { (progress:Double) in
            DispatchQueue.main.async(execute: { () -> Void in
                if progress < 100.0 {
                    self.statusLabel.text = String(format: "Uploading recording")
                } else {
                    self.statusLabel.text = "Waiting for response"
                }
            })
        }
        
        uploader.successHandler = { (data:Data, parts:[PartData]) -> Void in
            
            for part in parts {
                if part.headers["Content-Type"] == "application/json" {
                    if Config.Debug.General {
                        print(NSString(data: part.data, encoding: String.Encoding.utf8.rawValue))
                    }
                } else if part.headers["Content-Type"] == "audio/mpeg" {
                    do {
                        self.player = try AVAudioPlayer(data: part.data)
                        self.player?.delegate = self
                        self.player?.play()
                        
                        DispatchQueue.main.async(execute: { () -> Void in
                            self.statusLabel.text = "Playing response"
                        })
                    } catch let error {
                        DispatchQueue.main.async(execute: { () -> Void in
                            self.statusLabel.text = "Playing error: \(error)"
                            self.recordButton.isEnabled = true
                        })
                    }
                }
            }
            
        }
        
        try! uploader.start()
    }
    
    fileprivate func createMeatadata() -> String? {
        var rootElement = [String:Any]()
        
        let deviceContextPayload = ["streamId":"", "offsetInMilliseconds":"0", "playerActivity":"IDLE"]
        let deviceContext = ["name":"playbackState", "namespace":"AudioPlayer", "payload":deviceContextPayload] as [String : Any]
        rootElement["messageHeader"] = ["deviceContext":[deviceContext]]
        
        let deviceProfile = ["profile":"doppler-scone", "locale":"en-us", "format":"audio/L16; rate=16000; channels=1"]
        rootElement["messageBody"] = deviceProfile as AnyObject
        
        let data = try! JSONSerialization.data(withJSONObject: rootElement, options: JSONSerialization.WritingOptions(rawValue: 0))
        
        return NSString(data: data, encoding: String.Encoding.utf8.rawValue) as String?
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async(execute: { () -> Void in
            self.statusLabel.text = "Speak Now"
            self.recordButton.isEnabled = true
        })
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async(execute: { () -> Void in
            self.statusLabel.text = "Player error: \(error)"
            self.recordButton.isEnabled = true
        })
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func logoutClicked(_ sender: AnyObject) {
        AIMobileLib.clearAuthorizationState(nil)
        self.dismiss(animated: false, completion: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
