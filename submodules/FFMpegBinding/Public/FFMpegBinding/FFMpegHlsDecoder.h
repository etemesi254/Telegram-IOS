#ifndef FFMPEG_HLS_DECODER
#define FFMPEG_HLS_DECODER

#import <Foundation/Foundation.h>
#import "libavformat/avformat.h"
#import "libavcodec/avcodec.h"
#import "AVFoundation/AVFoundation.h"
#import "libswscale/swscale.h"

@interface HlsVideoData:NSObject
@property int width;
@property int height;
@end
@implementation HlsVideoData
@synthesize  width,height;
@end

@interface HlsOutputData : NSObject
@property int streamType; // 0, audio 1,video
@property (nullable) NSMutableData * audioData;
// NB (cae) using NSMUtableData has it creating an instance per frame
// which baloons up memory like no man's business
// Why does it do this? IDK, why doesn't audioData do this? IDK
@property (nullable) uint8_t* videoData;
@property int videoSize;
@property (nullable) HlsVideoData * videoParams;
@property int64_t pts;
@property int64_t duration;

- (int) cloneVideo: (HlsOutputData * _Nonnull) output;
- (int) cloneAudio: (HlsOutputData * _Nonnull) output;
- (void) dealloc;
@end

@implementation HlsOutputData
@synthesize streamType, audioData,videoData,videoParams,videoSize,pts,duration;

- (int) cloneVideo:(HlsOutputData * _Nonnull) output{
    if (output==NULL){
        return -1;
    }
    
    if (output.videoSize == 0){
        uint8_t *newVideoStorage = malloc(videoSize);
        if (newVideoStorage==NULL){
            return -1;
        }
        output.videoData = newVideoStorage;
    } else if (output.videoSize != videoSize){
        uint8_t *realloced = realloc(output.videoData, videoSize);
        if (realloced==NULL){
            free(output.videoData);
            return -1;
        }
        output.videoData = realloced;
        
    }
    output.videoSize =  videoSize;
    output.videoParams = [[HlsVideoData alloc] init];
    output.pts=pts;
    output.duration=duration;
    output.videoParams.width = videoParams.width;
    output.videoParams.height = videoParams.height;
    
    
    // copy
    memcpy(output.videoData, videoData, videoSize);
    return 0;
}
- (int) cloneAudio:(HlsOutputData * _Nonnull) output{
    if (output==NULL){
        return -1;
    }
    
    if (output.audioData.length != audioData.length){
        
        output.audioData = [NSMutableData dataWithLength:audioData.length];

    }
    output.pts = pts;
    output.duration = duration;
    memcpy(output.audioData.mutableBytes, audioData.bytes, audioData.length);
    
    return 1;
}
- (void)dealloc
{
    if (videoData!=NULL && self.videoSize!=0){
        free(videoData);
    }
}

@end



/// Single Context, stores an object that groups the whole
/// variables for a single audio or video context
@interface SingleCtx : NSObject
@property (nullable) AVCodecContext *ctx;
@property (nullable) AVFrame *frame;

/// Initialize the whole structure filling the frames , codecs and packets
- (int) initializeContext: (AVFormatContext * _Nonnull) ctx secondValue: (int) streamId thirdValue:(bool)isVideo;
/// Deallocate the structure freeing the contexts
- (void) dealloc;

- (int) initializeCodec:(AVFormatContext * _Nonnull) fmtCtx secondValue:(bool)isVideo thirdValue:(int)streamId;

@end

@interface AudioCtx :NSObject

@property int frameNo;
@property (nullable) SingleCtx *ctx;

- (int) initCtx: (AVFormatContext * _Nonnull) fmtCtx secondValue: (int) streamId;
- (int) convertFrameToPCM: (HlsOutputData * _Nullable )output;
- (int) decodeAudio: (AVPacket * _Nullable)pkt  secondValue: (HlsOutputData * _Nullable )output;

@end


@interface VideoCtx :NSObject
@property (nullable) SingleCtx *ctx;
@property (nullable) AVBufferRef *hwBufferRef;
@property (nullable) AVFrame *bgraFrame;
@property bool hwDecodingAvailable;
@property (nullable) struct SwsContext *resizer;


- (int) initCtx: (AVFormatContext * _Nonnull) fmtCtx secondValue: (int) streamId;
- (int) initHwDecoder :(AVFormatContext * _Nonnull) fmtCtx secondValue: (int) streamId;
- (int) decodeVideo: (AVPacket * _Nullable)pkt  secondValue: (HlsOutputData * _Nullable )output;
- (void) dealloc;

@end

@interface FFmpegHLSDecoder : NSObject
// The url we are fetching content from, can be file, http, tcp...
@property (nullable) NSString *url;

// number of filled streams for SingleStreamInfo
@property int nbStreams;

// The chosen video stream, -1 on initialization
@property int videoStreamIndex;
// The chosen audio stream, -1 on initialization
@property int audioStreamIndex;

@property bool metadataRead;
@property double frameRate;

// The format demuxer. Stored to read the format details
@property (nullable) AVFormatContext *avFmtCtx;
@property (nullable) AVPacket *pkt;

// Contexts
@property (nullable) VideoCtx *videoDecoderCtx;
@property (nullable) AudioCtx *audioDecoderCtx;
// Output storage, managed here to make it easy for me and watch for memory
// sizes
@property (nullable) HlsOutputData *output;

@property bool shouldDecodeAudio;
@property bool shouldDecodeVideo;


- (void) init:(NSString * _Nonnull)url;
- (void) dealloc;


- (int) readData;
- (int) getBestVideoStream;
- (int) getBestAudioStream;

- (int) setVideoDecoder:(int)videoStreamId;


- (int) initializeVideoCodec:(int)videoStreamId;
- (int) initializeAudioCodec:(int)audioStreamId;
- (int) seekTo: (double)timeStamp;


- (HlsOutputData * _Nullable )decode;
@end

#endif
