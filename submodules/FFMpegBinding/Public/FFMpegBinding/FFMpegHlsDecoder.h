#ifndef FFMPEG_HLS_DECODER
#define FFMPEG_HLS_DECODER

#import <Foundation/Foundation.h>
#import "libavformat/avformat.h"
#import "libavcodec/avcodec.h"
#import "AVFoundation/AVFoundation.h"

enum StreamType {
    Audio = 0,
    Video = 1
}typedef StreamType;

struct SingleStreamInfo {
    int64_t stream_id;
    int64_t duration;
    int64_t num_frames;
    int bits_per_sample;
    
    int video_width;
    int video_height;
    
    int audio_sample_rate;
    int audio_nb_channels;
    StreamType type;
} typedef SingleStreamInfo;

@interface HlsVideoData:NSObject
@property int width;
@property int height;
@property (nullable) NSMutableData *data;
@end
@implementation HlsVideoData
@synthesize  width,height,data;
@end

@interface HlsOutputData : NSObject
@property int streamType; // 0, audio 1,video
@property (nullable) NSMutableData * audioData;
@property (nullable) HlsVideoData * videoData;
@end

@implementation HlsOutputData
@synthesize streamType, audioData,videoData;
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
@property bool hwDecodingAvailable;

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
// Allocation of stream information, that can be shown on the swift side
@property (nullable) SingleStreamInfo  *streamInfo;


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


- (SingleStreamInfo const * _Nullable) getStreamInfo:(int) streamId;
- (HlsOutputData * _Nullable ) decode;
@end

#endif
