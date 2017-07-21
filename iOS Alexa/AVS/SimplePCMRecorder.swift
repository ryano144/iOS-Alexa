 //
//  SimplePCMRecorder.swift
//  AVSExample
//

import Foundation
import CoreAudio
import AudioToolbox

struct RecorderState {
    var setupComplete: Bool
    var dataFormat: AudioStreamBasicDescription
    var queue: UnsafeMutablePointer<AudioQueueRef?>
    var buffers: [AudioQueueBufferRef?]
    var recordFile: AudioFileID?
    var bufferByteSize: UInt32
    var currentPacket: Int64
    var isRunning: Bool
    var recordPacket: Int64
    var errorHandler: ((_ error:NSError) -> Void)?
}

extension Data {
    func castToCPointer<T>() -> T {
        return self.withUnsafeBytes { $0.pointee }
    }
}

class SimplePCMRecorder {
    
    fileprivate var recorderState: RecorderState
    
    init(numberBuffers:Int) {
        self.recorderState = RecorderState(
            setupComplete: false,
            dataFormat: AudioStreamBasicDescription(),
            queue: UnsafeMutablePointer<AudioQueueRef?>.allocate(capacity: 1),
            buffers: Array<AudioQueueBufferRef?>.init(repeating: (nil as AudioQueueBufferRef?), count: numberBuffers),
            recordFile: nil,
            bufferByteSize: 0,
            currentPacket: 0,
            isRunning: false,
            recordPacket: 0,
            errorHandler: nil)
    }
    
    deinit {
        self.recorderState.queue.deallocate(capacity: 1)
    }
    
    func setupForRecording(_ outputFileName:String, sampleRate:Float64, channels:UInt32, bitsPerChannel:UInt32, errorHandler: ((_ error:NSError) -> Void)?) throws {
        self.recorderState.dataFormat.mFormatID = kAudioFormatLinearPCM
        self.recorderState.dataFormat.mSampleRate = sampleRate
        self.recorderState.dataFormat.mChannelsPerFrame = channels
        self.recorderState.dataFormat.mBitsPerChannel = bitsPerChannel
        self.recorderState.dataFormat.mFramesPerPacket = 1
        self.recorderState.dataFormat.mBytesPerFrame = self.recorderState.dataFormat.mChannelsPerFrame * (self.recorderState.dataFormat.mBitsPerChannel / 8)
        self.recorderState.dataFormat.mBytesPerPacket = self.recorderState.dataFormat.mBytesPerFrame * self.recorderState.dataFormat.mFramesPerPacket

        self.recorderState.dataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
        
        self.recorderState.errorHandler = errorHandler
        
        try osReturningCall { AudioFileCreateWithURL(URL(fileURLWithPath: outputFileName) as CFURL, kAudioFileWAVEType, &self.recorderState.dataFormat, AudioFileFlags.dontPageAlignAudioData.union(.eraseFile), &(self.recorderState.recordFile)) }
        
        self.recorderState.setupComplete = true
    }
    
    
    
    
    
    func startRecording() throws {
        
        guard self.recorderState.setupComplete else { throw NSError(domain: Config.Error.ErrorDomain, code: Config.Error.PCMSetupIncompleteErrorCode, userInfo: [NSLocalizedDescriptionKey : "Setup needs to be called before starting"]) }
        
        let osAQNI = AudioQueueNewInput(&self.recorderState.dataFormat, { (inUserData:UnsafeMutableRawPointer?, inAQ:AudioQueueRef, inBuffer:AudioQueueBufferRef, inStartTime:UnsafePointer<AudioTimeStamp>, inNumPackets:UInt32, inPacketDesc:UnsafePointer<AudioStreamPacketDescription>?) -> Void in
            
            let internalRSP = inUserData!.assumingMemoryBound(to: RecorderState.self)
            
            if inNumPackets > 0 {
                var packets = inNumPackets
                
                let os = AudioFileWritePackets(internalRSP.pointee.recordFile!, false, inBuffer.pointee.mAudioDataByteSize, inPacketDesc, internalRSP.pointee.recordPacket, &packets, inBuffer.pointee.mAudioData)
                if os != 0 && internalRSP.pointee.errorHandler != nil {
                    internalRSP.pointee.errorHandler!(NSError(domain: NSOSStatusErrorDomain, code: Int(os), userInfo: nil))
                }

                internalRSP.pointee.recordPacket += Int64(packets)
            }
            
            if internalRSP.pointee.isRunning {
                let os = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
                if os != 0 && internalRSP.pointee.errorHandler != nil {
                    internalRSP.pointee.errorHandler!(NSError(domain: NSOSStatusErrorDomain, code: Int(os), userInfo: nil))
                }
            }
            
        } as AudioQueueInputCallback, &self.recorderState, nil, nil, 0, self.recorderState.queue)
        
        guard osAQNI == 0 else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(osAQNI), userInfo: nil) }
        
        let bufferByteSize = try self.computeRecordBufferSize(self.recorderState.dataFormat, seconds: 0.5)
        for i in 0 ..< self.recorderState.buffers.count {
            try osReturningCall { AudioQueueAllocateBuffer(self.recorderState.queue.pointee!, UInt32(bufferByteSize), &self.recorderState.buffers[i]) }
            
            try osReturningCall { AudioQueueEnqueueBuffer(self.recorderState.queue.pointee!, self.recorderState.buffers[i]!, 0, nil) }
        }
        
        try osReturningCall { AudioQueueStart(self.recorderState.queue.pointee!, nil) }
        
        self.recorderState.isRunning = true
    }
    
    func stopRecording() throws {
        self.recorderState.isRunning = false
        
        try osReturningCall { AudioQueueStop(self.recorderState.queue.pointee!, true) }
        try osReturningCall { AudioQueueDispose(self.recorderState.queue.pointee!, true) }
        try osReturningCall { AudioFileClose(self.recorderState.recordFile!) }
    }
    
    fileprivate func computeRecordBufferSize(_ format:AudioStreamBasicDescription, seconds:Double) throws -> Int {
        
        let framesNeededForBufferTime = Int(ceil(seconds * format.mSampleRate))
        
        if format.mBytesPerFrame > 0 {
            return framesNeededForBufferTime * Int(format.mBytesPerFrame)
        } else {
            var maxPacketSize = UInt32(0)
            
            if format.mBytesPerPacket > 0 {
                maxPacketSize = format.mBytesPerPacket
            } else {
                try self.getAudioQueueProperty(kAudioQueueProperty_MaximumOutputPacketSize, value: &maxPacketSize)
            }
            
            var packets = 0
            if format.mFramesPerPacket > 0 {
                packets = framesNeededForBufferTime / Int(format.mFramesPerPacket)
            } else {
                packets = framesNeededForBufferTime
            }
            
            if packets == 0 {
                packets = 1
            }
            
            return packets * Int(maxPacketSize)
        }
        
    }
    
    fileprivate func osReturningCall(_ osCall: () -> OSStatus) throws {
        let os = osCall()
        if os != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(os), userInfo: nil)
        }
    }
//    
//    func getInputPower() -> Int
//    {
//        var levelMeterSize = sizeof(AudioQueueLevelMeterState)
//        try! getAudioQueueProperty(kAudioQueueProperty_CurrentLevelMeterDB, value: &levelMeterSize)
//        return levelMeterSize
//    }
    
    fileprivate func getAudioQueueProperty<T>(_ propertyId:AudioQueuePropertyID, value:inout T) throws {
        
        let propertySize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        propertySize.pointee = UInt32(MemoryLayout<T>.size)
        
        let os = AudioQueueGetProperty(self.recorderState.queue.pointee!,
            propertyId,
            &value,
            propertySize)
        
        propertySize.deallocate(capacity: 1)
        
        guard os == 0 else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(os), userInfo: nil) }
        
    }
}
