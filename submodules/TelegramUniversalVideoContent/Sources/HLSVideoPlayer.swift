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
    var engine: AVAudioEngine?
    var playerNode: AVAudioPlayerNode?
    var streamingFormat: AVAudioFormat?
    var bytesPerSample:Int
    var volume:Float
    var shouldPlay = true;
    
    public init(volume:Float) {
        self.engine = nil
        self.playerNode = nil
        self.streamingFormat = nil
        self.volume = volume;
        self.bytesPerSample=1;
        
    }
    
    
    func scheduleAudioPacket(_ data: Data) {
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
        playerNode?.scheduleBuffer(buffer)
    }
    
    func start() {
        do {
            try engine?.start()
            playerNode?.play()
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }
}

class HLSVideoPlayer {
    
    
    
    let decoder:FFmpegHLSDecoder
    /// Use global queue for dispatch
    let queue: DispatchQueue
    let dataGroup:DispatchGroup
    var metaDataRead:Bool = false
    var audioPlayer:HLSAudioPlayer
    var url: String
    public var actionAtItemEnd: HlsActionAtItemEnd = HlsActionAtItemEnd.none
    public var rate:Float = 1.0
    
    var _volume :Float;
    
    public var volume:Float {
        get{
            return _volume;
        }
        set(newVolume){
            _volume = newVolume;
            self.audioPlayer.volume=newVolume;
        }
    }
    
    
    
    public init(url:String){
        self.url = url;
        decoder = FFmpegHLSDecoder()
        _volume = 1.0
        decoder.`init`(url)
        queue = DispatchQueue.global()
        dataGroup = DispatchGroup()
        audioPlayer = HLSAudioPlayer(volume: 1.0)
    }
    
    public func setUrl(url:String){
        self.decoder.`init`(url);
        
    }
    public func setVolume(volume:Float){
        self.audioPlayer.volume = volume;
    }
    public func getVolume()->Float{
        return self.audioPlayer.volume;
    }
    public func readData(){
        print("Starting Metadata read");
        dataGroup.enter();
        metaDataRead=false;
        
        queue.async {
            self.setupAudio();
        }
    }
    func setupAudio(){
        if (self.decoder.readData()<0){
            print("Cannot initialize decoder context");
            return ;
        }
        self.playAudio();
        
        self.dataGroup.leave();
        print("Finished reading metadata");
        self.audioPlayer.start();
        
        self.metaDataRead = true;
        
        while true{
            let packet = self.decoder.decode();
            if (packet != nil){
                
                if (packet?.streamType==0){
                    
                    self.audioPlayer.scheduleAudioPacket(packet!.audioData! as Data);
                }
                if (packet?.streamType==1){
                    // video
//                    let frame = self.decoder.avFmtCtx!.pointee.streams[Int(self.decoder.videoStreamIndex)];
//                    let c = frame.pointee!.
//                    
                    
                }
            } else{
                print("Packet was nil");
                break;
            }
        }
    }
    
    public func playAudio(){
        
        
        let streamInformation = self.decoder.getStreamInfo(self.decoder.audioStreamIndex);
        guard streamInformation  != nil else{

            return ;
        }
        var commonFormat = AVAudioCommonFormat.pcmFormatInt16;
        
        self.audioPlayer.engine = AVAudioEngine()
        self.audioPlayer.playerNode = AVAudioPlayerNode()
        
        let sampleRate = streamInformation!.pointee.audio_sample_rate;
        let numberChannels = streamInformation!.pointee.audio_nb_channels;
        
        let decoder = self.decoder.audioDecoderCtx!;
        
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
        
        self.audioPlayer.engine?.attach(self.audioPlayer.playerNode!);
        
        self.audioPlayer.engine?.connect(
            self.audioPlayer.playerNode!,
            to: self.audioPlayer.engine!.mainMixerNode,
            format: self.audioPlayer.streamingFormat!
        )
        
    }
    public func currentTime()->CMTime{
        //double timestamp = frame->best_effort_timestamp * av_q2d(st->time_base);
        return CMTime(value: 4, timescale: 1);
        
    }
    public func pause(){
       // self.audioPlayer
        
    }
    public  func play(){
        self.readData();
        
    }
    public func seek(to:CMTime){
     
    }
}
