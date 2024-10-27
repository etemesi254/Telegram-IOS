//
//  HLSVideoPlayer.swift
//  Telegram
//
//  Created by Caleb Etemesi on 13/10/2024.
//

import AVFoundation
import FFMpegBinding
import AccountContext
import RangeSet
import SwiftSignalKit
import UniversalMediaPlayer
import Display
import AsyncDisplayKit
import UIKit

enum PlayObservers{
    //    case isPlaying
    //    case isBuffering
    case rateChange
}

enum HlsActionAtItemEnd{
    case advance
    case play
    case pause
    case none
}



class HLSAudioPlayer{
    var engine: AVAudioEngine
    var playerNode: AVAudioPlayerNode
    var streamingFormat: AVAudioFormat?
    var bytesPerSample:Int
    var volume:Float
    var shouldPlay = true;
    var initializedFrames = false;
    var playedAudioFrames:Int = 0
    
    
    public init(volume:Float) {
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.streamingFormat = nil
        self.volume = volume;
        self.bytesPerSample=1;
        
    }
    
    
    func scheduleAudioPacket(data:  Data) {
        let buffer = AVAudioPCMBuffer(pcmFormat: streamingFormat!,
                                      frameCapacity: UInt32(data.count)/(UInt32(self.bytesPerSample) * streamingFormat!.channelCount)
        )!
        
        let frameCapacity = buffer.frameCapacity;
        buffer.frameLength = frameCapacity;
        
        self.engine.mainMixerNode.volume = volume;
        // Copy network data into audio buffer
        if (streamingFormat!.channelCount == 1){
            // Mono Audio
            if (streamingFormat?.commonFormat == AVAudioCommonFormat.pcmFormatInt16){
                let audioBufferPointer = buffer.int16ChannelData?[0]
                data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
                    if let sourcePointer = bufferPointer.bindMemory(to: Int16.self).baseAddress {
                        audioBufferPointer?.update(from: sourcePointer, count: Int(frameCapacity))
                    }
                }
            } else if (streamingFormat?.commonFormat == AVAudioCommonFormat.pcmFormatInt32){
                let audioBufferPointer = buffer.int32ChannelData?[0]
                data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
                    if let sourcePointer = bufferPointer.bindMemory(to: Int32.self).baseAddress {
                        audioBufferPointer?.update(from: sourcePointer, count: Int(frameCapacity))
                    }
                }
            } else if (streamingFormat?.commonFormat==AVAudioCommonFormat.pcmFormatFloat32){
                let audioBufferPointer = buffer.floatChannelData?[0]
                
                data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
                    if let sourcePointer = bufferPointer.bindMemory(to: Float.self).baseAddress {
                        
                        audioBufferPointer?.update(from: sourcePointer, count: Int(frameCapacity))
                    }
                }
            }
        } else{
            if (streamingFormat?.commonFormat==AVAudioCommonFormat.pcmFormatFloat32){
                // stereo audio
                let audioBufferPointer = buffer.floatChannelData?[0]
                let audioBufferPointer2 = buffer.floatChannelData?[1]
                
                data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
                    if let sourcePointer = bufferPointer.bindMemory(to: Float.self).baseAddress {
                        audioBufferPointer?.update(from: sourcePointer, count: Int(frameCapacity))
                        audioBufferPointer2?.update(from: sourcePointer.advanced(by: Int(frameCapacity)),
                                                    count: Int(frameCapacity))
                    }
                }
            } else if (streamingFormat?.commonFormat==AVAudioCommonFormat.pcmFormatInt16) {
                // stereo audio
                let audioBufferPointer = buffer.int16ChannelData?[0]
                let audioBufferPointer2 = buffer.int16ChannelData?[1]
                
                data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
                    if let sourcePointer = bufferPointer.bindMemory(to: Int16.self).baseAddress {
                        audioBufferPointer?.update(from: sourcePointer, count: Int(frameCapacity))
                        audioBufferPointer2?.update(from: sourcePointer.advanced(by: Int(frameCapacity)),
                                                    count: Int(frameCapacity))
                    }
                }
            } else if (streamingFormat?.commonFormat==AVAudioCommonFormat.pcmFormatInt32) {
                // stereo audio
                let audioBufferPointer = buffer.int32ChannelData?[0]
                let audioBufferPointer2 = buffer.int32ChannelData?[1]
                
                data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
                    if let sourcePointer = bufferPointer.bindMemory(to: Int32.self).baseAddress {
                        audioBufferPointer?.update(from: sourcePointer, count: Int(frameCapacity))
                        audioBufferPointer2?.update(from: sourcePointer.advanced(by: Int(frameCapacity)),
                                                    count: Int(frameCapacity))
                    }
                }
            }
        }
        playerNode.scheduleBuffer(buffer,
                                  completionCallbackType:AVAudioPlayerNodeCompletionCallbackType.dataPlayedBack,
                                  completionHandler:  self.audioPlayed)
    }
    
    func audioPlayed(played:AVAudioPlayerNodeCompletionCallbackType) -> Void{
        if (played == AVAudioPlayerNodeCompletionCallbackType.dataPlayedBack){
            self.playedAudioFrames += 1;
        }
        return ()
    }
    
    func start() {
        if (!initializedFrames){
            return;
        }
        do {
            try engine.start()
            playerNode.play()
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }
    func pause() {
        
        if (engine.isRunning){
            engine.pause()
        }
        if (playerNode.isPlaying){
            playerNode.pause()
        }
    }
    func play(){
        if (!initializedFrames){
            return;
        }
        if (engine.isRunning){
            do{
                try engine.start()
            } catch {
                print("Error starting audio engine: \(error)")
            }
        }
        if (playerNode.isPlaying){
            playerNode.play()
        }
    }
    func stop(){
        if (initializedFrames){
            self.engine.stop();
            self.playerNode.stop();
        }
    }
}

class HLSVideoPlayer {
    private let queue: DispatchQueue
    private let updaterQueue:DispatchQueue

    private let dataGroup:DispatchGroup
    private let videoBufferTracker:DispatchGroup
    private let _videoBufferSize = 10;
    private let _audioBufferSize = 20;
    
    
    private var audioPlayer:HLSAudioPlayer
    private var videoEnd:Bool = false;
    private var url: String
    private var renderer: HlsPlayerView
    private var syncer: CADisplayLink?
    private var _volume :Float;
    private var videoBuffer:RingBuffer
    private var audioBuffer:RingBuffer
    
    public let decoder:FFmpegHLSDecoder
    
    public var metaDataRead:Bool = false
    public var actionAtItemEnd: HlsActionAtItemEnd = HlsActionAtItemEnd.none
    public var _rate:Float = 0.0
    public var fps:Int = 0;
    public var shouldDecode = true;
    public var audioStarted = false;
    public var isBuffering = false;
    public var isPaused = false;
    public var onRateChange:(Float)->Void
    
    public var rate:Float {
        get{
            return _rate;
        }
        set(newRate){
            if (newRate != _rate){
                _rate = newRate;
                //self.onRateChange(_rate)
            }
        }
    }
    public var volume:Float {
        get{
            return _volume;
        }
        set(newVolume){
            _volume = newVolume;
            self.audioPlayer.volume = newVolume;
        }
    }
    
    public init(url:String,displayLocation:ASDisplayNode,onRateChange:@escaping (Float)->Void){
        self.url = url;
        decoder = FFmpegHLSDecoder()
        _volume = 1.0
        decoder.`init`(url)
        queue = DispatchQueue(label: "decoder_thread",qos:.background);
        updaterQueue = DispatchQueue(label: "updater_thread",qos: .background);
        dataGroup = DispatchGroup()
        audioPlayer = HLSAudioPlayer(volume: 1.0)
        renderer = HlsPlayerView(frame: displayLocation.frame, device: nil)
        videoBuffer = RingBuffer(count:_videoBufferSize)
        audioBuffer = RingBuffer(count:_audioBufferSize)
        videoBufferTracker=DispatchGroup()
        self.onRateChange=onRateChange;
        
        
        let displayLink = CADisplayLink(target:self, selector: #selector(step))
        
        // nos set up linker
        displayLink.add(to: .current, forMode: .default)
        displayLink.isPaused = true;
        
        self.syncer = displayLink;
        
        // will 30 fps
        displayLocation.setViewBlock({
            return  self.renderer;
        });
    }
    deinit{
        self.dealloc();
        
    }
    
    func calculateAppropriateFps(){
        
    }
    public func dealloc(){
        self.audioPlayer.stop()
        self.syncer?.invalidate()
        self.videoBuffer.dealloc();
        self.shouldDecode=false;
    }
    @objc func step(displaylink: CADisplayLink) {
        
        if (!self.videoBuffer.isEmpty){
            
            // self.videoBufferTracker.wait();
            self.isBuffering = false;
            let buffer = self.videoBuffer.read()
            
            guard let noVideobuffer = buffer else {
                return
            }
            
            
            self.renderer.updateFrame(with: noVideobuffer.videoData!,
                                      width: Int(noVideobuffer.videoParams!.width),
                                      height: Int(noVideobuffer.videoParams!.height)
                                      
            )
            self.videoBuffer.acknowledgeRead()
            
            self.shouldDecode = true
            self.rate = 1
            
            
        } else{
            // frame hang
            self.rate = 0
            self.isBuffering = true
        }
        
        self.updaterQueue.sync {
            self.onRateChange(self.rate);
        }
        if (self.videoEnd && self.videoBuffer.isEmpty){
            // video is over
            self.dealloc();
            self.syncer?.isPaused=true
        }
    }
    
    public func setUrl(url:String){
        self.decoder.`init`(url);
    }
    
    public func readData(){
        print("Starting Metadata read");
        metaDataRead=false;
        
        self.rate = 0
        if (self.decoder.readData()<0){
            print("Cannot initialize decoder context");
            return ;
        }
        self.rate = 1
        self.metaDataRead = true;
        // setup audio stream
        self.initAudioContext()
        
        self.fps = Int(self.decoder.frameRate)
        
        
        // pause if frame rate is not a number we understand
        if (self.decoder.frameRate != 0){
            // set frame rate to be same as the video frame rate
            self.syncer?.preferredFramesPerSecond = Int(self.decoder.frameRate)
            self.syncer?.isPaused = false
        } else{
            self.syncer?.isPaused = true
        }
        return;
        
    }
    func decodeAndRender(){
        
        queue.async {
            if (!self.audioStarted){
                self.audioPlayer.start();
                self.audioStarted = true;
            }
            
            while true{
                if (!self.shouldDecode){
                    // sleep for 10 ms
                    // 10 ms
                    let ms = 1000
                    usleep(useconds_t(10*ms))
                    
                    continue;
                }
                
                if (self.isPaused){

                    break;
                }
                if (self.videoEnd){
                    break;
                }
                let maybeNil = self.decoder.decode();
                guard let packet = maybeNil else{
                    self.videoEnd=true;
                    print("Packet was nil");
                    break;
                }
                
                if (packet.streamType==0){
                    if (self.audioPlayer.initializedFrames){
                        self.audioPlayer.scheduleAudioPacket(data:packet.audioData! as Data);
                    }
                }
                else if (packet.streamType==1){
                    
                    DispatchQueue.global(qos:.userInteractive).sync{
                        let c =  self.videoBuffer.lookahead;
                        self.videoBuffer.lookahead += 1;
                        
                        while (true){
                        
                            if (self.videoBuffer.isFull){
                                // buffer is full, so we wait for it to
                                // have space and retry

                                // disable decoding until we have space for buffering
                                // the displayer will make it that on frame
                                // display shouldDecode is set to true
                                self.shouldDecode=false;
 
                                // 10 ms
                                let ms = 1000
                                usleep(useconds_t(10*ms))
                                
                                
                                continue
                            }
                            
                            if (!self.videoBuffer.writeVideo(packet,position:c)){
                                // sleep for 10 ms, if we failed to write the packet
                                let ms = 1000
                                usleep(useconds_t(10*ms));
                                continue;
                            }
                            // we wrote the buffer, so we are good
                            break;
                        }
                    }
                }
            }
            self.audioPlayer.stop();
        }
    }

    private func initAudioContext(){
        
        let streamInformation = self.decoder.avFmtCtx?.pointee.streams[Int(self.decoder.audioStreamIndex)];
        guard streamInformation  != nil else{
            
            return ;
        }
        let decoder = self.decoder.audioDecoderCtx!;
        
        var commonFormat = AVAudioCommonFormat.pcmFormatInt16;
        
        
        let sampleRate = streamInformation!.pointee.codecpar.pointee.sample_rate;
        let numberChannels = streamInformation!.pointee.codecpar.pointee.ch_layout.nb_channels;
        let audioRawFormat = decoder.ctx?.ctx?.pointee.sample_fmt;
        
        
        if (audioRawFormat != nil){
            switch audioRawFormat{
            case .none:
                commonFormat = AVAudioCommonFormat.otherFormat;
            case .some(let c):
                // set format
                switch c {
                case AV_SAMPLE_FMT_S16,AV_SAMPLE_FMT_S16P:
                    commonFormat = AVAudioCommonFormat.pcmFormatInt16;
                    self.audioPlayer.bytesPerSample = 2;
                    
                case AV_SAMPLE_FMT_S32,AV_SAMPLE_FMT_S32P:
                    commonFormat=AVAudioCommonFormat.pcmFormatInt32;
                    self.audioPlayer.bytesPerSample = 4;
                    
                case AV_SAMPLE_FMT_FLT,AV_SAMPLE_FMT_FLTP:
                    commonFormat = AVAudioCommonFormat.pcmFormatFloat32;
                    self.audioPlayer.bytesPerSample = 4;
                    
                case AV_SAMPLE_FMT_DBL,AV_SAMPLE_FMT_DBLP:
                    commonFormat=AVAudioCommonFormat.pcmFormatFloat64;
                    self.audioPlayer.bytesPerSample = 8;
                default:
                    commonFormat = AVAudioCommonFormat.otherFormat;
                }
            }
        }
        
        self.audioPlayer.streamingFormat = AVAudioFormat(
            commonFormat:commonFormat,
            sampleRate: Double(sampleRate),
            channels:AVAudioChannelCount(numberChannels),
            // BUG: Can't have this as true as it is not supported for CoreAudio
            // Throws kAudioUnitErr_FormatNotSupported
            // so leaving it as false, and ensuring samples are correct.
            interleaved:false)!;
        
        self.audioPlayer.engine.attach(self.audioPlayer.playerNode);
        
        self.audioPlayer.engine.connect(
            self.audioPlayer.playerNode,
            to: self.audioPlayer.engine.mainMixerNode,
            format: self.audioPlayer.streamingFormat!
        )
        self.audioPlayer.initializedFrames=true;
        
    }
    public func currentTime()->CMTime{
        //
        if (self.fps==0){
            return CMTime(value: 0, timescale: 1)
        }
        let noFrames = self.videoBuffer.readIndex/self.fps;
        return CMTime(value: Int64(noFrames), timescale: 1);
        
    }
    public func pause(){
        // self.audioPlayer
        self.audioPlayer.pause()

        self.isPaused = true;
        self.rate = 0;
        
        
    }
    public func play(){
        if (!self.metaDataRead){
            self.readData();
        }
        self.audioPlayer.start()
        self.isPaused = false;
        self.rate = 1
        self.syncer?.isPaused = false;
        self.decodeAndRender()
        
        
    }
    public func seek(to:CMTime){
        // clear audio
        self.audioPlayer.playerNode.stop();
        
        self.isPaused=true;
        // go to location
        self.decoder.seek(to: to.seconds)
        self.isPaused=false;
        self.audioPlayer.start()
        self.videoBuffer.clear()
        self.shouldDecode=true;
        self.decodeAndRender()
        //self.decoder.seek(to: s)
        
    }
}
