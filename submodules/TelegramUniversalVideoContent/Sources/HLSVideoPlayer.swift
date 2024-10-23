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
        self.engine.stop();
        self.playerNode.stop();
    }
}

class HLSVideoPlayer {
    private let queue: DispatchQueue
    private let dataGroup:DispatchGroup
    
    private var audioPlayer:HLSAudioPlayer
    private var url: String
    private var renderer: HlsPlayerView
    private var viewLocation: ASDisplayNode
    private var _volume :Float;

    
    public let decoder:FFmpegHLSDecoder

    public var metaDataRead:Bool = false
    public var actionAtItemEnd: HlsActionAtItemEnd = HlsActionAtItemEnd.none
    public var rate:Float = 1.0
    public var shouldDecode = true;
    public var volume:Float {
        get{
            return _volume;
        }
        set(newVolume){
            _volume = newVolume;
            self.audioPlayer.volume = newVolume;
        }
    }
    
    
    
    public init(url:String,displayLocation:ASDisplayNode){
        self.url = url;
        decoder = FFmpegHLSDecoder()
        _volume = 1.0
        decoder.`init`(url)
        queue = DispatchQueue(label: "decoder_thread",qos:.background);
        dataGroup = DispatchGroup()
        audioPlayer = HLSAudioPlayer(volume: 1.0)
        viewLocation = displayLocation
        renderer = HlsPlayerView(frame: displayLocation.frame, device: nil)
        displayLocation.setViewBlock({
            return self.renderer;
        });
    }
    deinit{
        self.audioPlayer.stop()
        self.shouldDecode=false;
        
    }
    
    public func setUrl(url:String){
        self.decoder.`init`(url);
    }
    
    public func readData(){
        print("Starting Metadata read");
        metaDataRead=false;
        
        self.rate=0;
        if (self.decoder.readData()<0){
            print("Cannot initialize decoder context");
            return ;
        }
        self.rate=1;
        self.metaDataRead=true;
        // setup audio stream
        self.initAudioContext();
        return;
        
    }
    func decodeAndRender(){
        // don't allow multiple calls
        if (self.dataGroup.wait(timeout: DispatchTime(uptimeNanoseconds: 100)) == DispatchTimeoutResult.timedOut){
            // we don't allow multiple calls to decodeAndRender()
            // so do this to ensure we don't get two decode threads running
            return;
        }
        self.dataGroup.enter();

        queue.async {
            self.audioPlayer.start();
            
            while self.shouldDecode{
                
                let packet = self.decoder.decode();
                if (packet != nil){
                    
                    if (packet?.streamType==0){                        
                        
                        self.audioPlayer.scheduleAudioPacket(data:packet!.audioData! as Data);
                    }
                    else if (packet?.streamType==1){
                        let width  = Int(packet!.videoParams!.width);
                        let height = Int(packet!.videoParams!.height);
                        
            
                        let data = packet!.videoData!;
                        
                        DispatchQueue.main.async{
                
                            self.renderer.updateFrame(with: data, width: width, height: height)
                        }
                              
                        
                    }
                } else{
                    print("Packet was nil");
                    break;
                }
            }
            self.dataGroup.leave();
        }
        self.audioPlayer.stop();


    }
    
    private func updateAudioFrame(){
        
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
        let noFrames = self.audioPlayer.playedAudioFrames/44;
        return CMTime(value: Int64(noFrames), timescale: 1);
        
    }
    public func pause(){
       // self.audioPlayer
        self.audioPlayer.pause()
        self.rate = 0;

        
    }
    public func play(){
        if (!self.metaDataRead){
            self.readData();
        }
        self.audioPlayer.start()
        self.rate = 1;
        // see if we can acces the semaphore
        
        self.decodeAndRender()

        
    }
    public func seek(to:CMTime){
        // clear audio
        self.audioPlayer.playerNode.stop();
        
        // go to location
        //self.decoder.seek(to: s)
     
    }
}
