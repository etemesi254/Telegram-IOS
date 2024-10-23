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
@end

@implementation HlsOutputData
@synthesize streamType, audioData,videoData,videoParams,videoSize;
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

@property int filled;

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


- (HlsOutputData * _Nullable ) decode;
@end

#endif
