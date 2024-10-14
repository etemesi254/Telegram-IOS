#import <FFMpegBinding/FFMpegHlsDecoder.h>

#import "libavcodec/avcodec.h"
#import "libavformat/avformat.h"
#include "libavutil/timestamp.h"


@implementation SingleCtx

- (int) initializeContext:(AVFormatContext *)ctx secondValue:(int)streamId thirdValue:(bool)isVideo {
    
    int ret = -1;
    ret = [self initializeCodec:ctx secondValue:isVideo thirdValue:streamId];
    if (ret <0){
        NSLog(@"Could not initialize codec");
        return ret;
    }
    // initialize frame and packet
    _frame = av_frame_alloc();
    if (!_frame) {
        fprintf(stderr, "Could not allocate frame\n");
        ret = AVERROR(ENOMEM);
        return ret;
    }
    
    ret = 0;
    NSLog(@"Successfully initialized context");
    return ret;
}
- (int)initializeCodec:(AVFormatContext *)fmtCtx secondValue:(_Bool)isVideo thirdValue:(int)streamId{
    int ret = -1;
    enum AVMediaType type= isVideo?AVMEDIA_TYPE_VIDEO:AVMEDIA_TYPE_AUDIO;
    if (fmtCtx != NULL){
        AVStream *st = fmtCtx->streams[streamId];
        
        /* find decoder for the stream */
        const AVCodec *dec = avcodec_find_decoder(st->codecpar->codec_id);
        
        if (!dec) {
            fprintf(stderr, "Failed to find %s codec\n",
                    av_get_media_type_string(type));
            return AVERROR(EINVAL);
        }
        /* Allocate a codec context for the decoder */
        _ctx = avcodec_alloc_context3(dec);
        if (!_ctx) {
            fprintf(stderr, "Failed to allocate the %s codec context\n",
                    av_get_media_type_string(type));
            return AVERROR(ENOMEM);
        }
        
        /* Copy codec parameters from input stream to output codec context */
        if ((ret = avcodec_parameters_to_context(_ctx, st->codecpar)) < 0) {
            fprintf(stderr, "Failed to copy %s codec parameters to decoder context\n",
                    av_get_media_type_string(type));
            return ret;
        }
        
        /* Init the decoders */
        if ((ret = avcodec_open2(_ctx, dec, NULL)) < 0) {
            fprintf(stderr, "Failed to open %s codec\n",
                    av_get_media_type_string(type));
            return ret;
            
        }
        printf("Codec Initialized Successfully\n");
        return ret;
    }
    fprintf(stderr, "AVFormatCtx is null, did you initialize it");
    return ret;
}

- (void) dealloc {
    avcodec_free_context(&_ctx);
    av_frame_free(&_frame);
}

@end

@implementation AudioCtx

- (int) initCtx:(AVFormatContext *)fmtCtx secondValue:(int)streamId{
    SingleCtx *context = [[SingleCtx alloc] init];
    [context initializeContext: fmtCtx secondValue:streamId thirdValue:false];
    _ctx = context;
    int sampleRate = _ctx.ctx->sample_rate;
    int channelCount = _ctx.ctx->ch_layout.nb_channels;
    
    const char *sampleFormat = av_get_sample_fmt_name( _ctx.ctx->sample_fmt);
    int bytesPerSample = av_get_bytes_per_sample(_ctx.ctx->sample_fmt);
    
    int maxFrameSize = sampleRate * channelCount * bytesPerSample;
    
    _reusablePcmData = [NSMutableData dataWithLength:maxFrameSize];
    
    printf("Audio Sample format: %s Bytes per sample: %d\n",sampleFormat,bytesPerSample);
    
    
    return 0;
}
- (NSData * _Nullable) decodeAudio:(AVPacket * _Nullable) pkt{
    int ret = 0;
    // submit the packet to the decoder
    ret = avcodec_send_packet(_ctx.ctx, pkt);
    if (ret < 0) {
        fprintf(stderr, "Error submitting a packet for decoding (%s)\n", av_err2str(ret));
        return NULL;
    }
    
    // get all the available frames from the decoder
    while (ret >= 0) {
        ret = avcodec_receive_frame(_ctx.ctx, _ctx.frame);
        if (ret < 0) {
            // those two return values are special and mean there is no output
            // frame available, but there were no errors during decoding
            if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN))
                return NULL;
            
            fprintf(stderr, "Error during decoding (%s)\n", av_err2str(ret));
            return NULL;
        }
        
        assert(_ctx.ctx->codec->type==AVMEDIA_TYPE_AUDIO &&"A codec that is not audio sent to audio decoder");
        
        AVFrame *frame = _ctx.frame;
        printf("audio_frame n:%d nb_samples:%d pts:%s\n",
               _frameNo++, frame->nb_samples,
               av_ts2timestr(frame->pts,&_ctx.ctx->time_base));
        
        NSData *data = [self convertFrameToPCM];
        
        av_frame_unref(_ctx.frame);
        
        return data;
    }

    return NULL;
}
- (NSData * _Nonnull) convertFrameToPCM{
    
    printf("Converting frame to PCM\n");
    int channelCount = _ctx.ctx->ch_layout.nb_channels;
    int bytesPerSample = av_get_bytes_per_sample(_ctx.ctx->sample_fmt);
    
    
    int dataSize = _ctx.frame->nb_samples * channelCount * bytesPerSample;
    
    // Ensure our reusable buffer is large enough
    if (dataSize > _reusablePcmData.length) {
        _reusablePcmData.length = dataSize;
    }
    
    uint8_t *pcmBuffer = (uint8_t *)_reusablePcmData.mutableBytes;
    
    // Handle planar and packed formats
    if (av_sample_fmt_is_planar(_ctx.ctx->sample_fmt)) {
        // Planar format (e.g., AV_SAMPLE_FMT_S16P)
        for (int i = 0; i < _ctx.frame->nb_samples; i++) {
            for (int ch = 0; ch < channelCount; ch++) {
                memcpy(pcmBuffer, &_ctx.frame->data[ch][i*bytesPerSample], bytesPerSample);
                // increment bytes per sample
                pcmBuffer += bytesPerSample;
            }
        }
    } else {
        // Packed format (e.g., AV_SAMPLE_FMT_S16)
        memcpy(pcmBuffer, _ctx.frame->data[0], dataSize);
    }
    
    // Return a new NSData object that references the filled portion of our buffer
    return [NSData dataWithBytesNoCopy:_reusablePcmData.mutableBytes length:dataSize freeWhenDone:NO];
}

- (void) dealloc{
    
    
}
@end

@implementation VideoCtx

- (int) initCtx:(AVFormatContext *)ctx secondValue:(int)streamId{
    SingleCtx *context = [[SingleCtx alloc] init];
    [context initializeContext: ctx secondValue:streamId thirdValue:true];
    _ctx = context;
    return 0;
}
- (void) dealloc{
    
    
}
@end


@implementation FFmpegHLSDecoder

- (void) init:(NSString *)url{
    NSLog(@"Calling Init ");
    _url =url;
    _videoStreamIndex = -1;
    _audioStreamIndex = -1;
    _shouldDecodeAudio=true;
    _shouldDecodeVideo=true;
    
    _pkt = av_packet_alloc();
    if (!_pkt) {
        fprintf(stderr, "Could not allocate packet\n");
    }
}
// tutorial https://github.com/Golim4r/OpenGL-Video-Player/blob/master/src/Decoder.cpp

- (void) readData{
    
    if (_url==nil){
        NSLog(@"URL not initialized, call init()!!!");
        return;
    }
    
    
    NSLog(@"Reading HLS Stream");
    // https://ffmpeg.org/doxygen/5.1/demuxing_decoding_8c-example.html#_a0
    AVFormatContext *fmt_ctx = NULL;
    
    const char *cfilename=[_url UTF8String];
    printf("Filename: %s\n",cfilename);
    
    int ret = avformat_open_input(&fmt_ctx, cfilename, NULL, NULL);
    /* open input file, and allocate format context */
    if (ret<0) {
        fprintf(stderr, "cannot open file %d\n",ret);
        return ;
    }
    _av_format=fmt_ctx;
    
    
    /* retrieve stream information */
    if (avformat_find_stream_info(fmt_ctx, NULL) < 0) {
        ret = -1;
        fprintf(stderr, "Could not find stream information\n");
        return;
    }
    
    _nbStreams= fmt_ctx->nb_streams;
    _streamInfo = malloc(sizeof(SingleStreamInfo) * _nbStreams);
    
    for (int i=0; i<_nbStreams; i++) {
        SingleStreamInfo *stream = &_streamInfo[i];
        
        const AVStream *st = fmt_ctx->streams[i];
        
        if (st->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            if (st->codecpar->codec_id == AV_CODEC_ID_H264) {
                stream->stream_id = st->id;
                stream->duration = st->duration;
                stream->num_frames = st->nb_frames;
                stream->type = Video;
                stream->video_width = st->codecpar->width;
                stream->video_height = st->codecpar->height;
                stream->bits_per_sample = st->codecpar->bits_per_raw_sample;
                _filled++;
            } else {
                fprintf(stderr, "Unsupported video codec type %s\n", avcodec_get_name(st->codecpar->codec_id));
                ret = -1;
            }
        } else if (st->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            if (st->codecpar->codec_id == AV_CODEC_ID_AAC) {
                stream->stream_id = st->id;
                stream->duration = st->duration;
                stream->num_frames = st->nb_frames;
                stream->type = Audio;
                stream->bits_per_sample = st->codecpar->bits_per_raw_sample;
                stream->audio_sample_rate = st->codecpar->sample_rate;
                stream->audio_nb_channels=st->codecpar->ch_layout.nb_channels;
                
                _filled++;
            } else {
                fprintf(stderr, "Unsupported audio codec type %s\n", avcodec_get_name(st->codecpar->codec_id));
                ret = -1;
            }
        }
        
    }
    // get best streams now
    [self getBestVideoStream];
    [self getBestAudioStream];
    if (_videoStreamIndex >0 && _nbStreams){
        [self initializeVideoCodec:(int)_videoStreamIndex];
    }
    if (_audioStreamIndex > 0 && _nbStreams){
        [self initializeAudioCodec:(int)_audioStreamIndex];
    }
    
}
- (NSData * _Nullable) decodeAudio{
    printf("Decoding Audio");
    int ret = 0;
    /* read frames from the file */
    while (av_read_frame(_av_format, _pkt) >= 0) {
        if (_pkt->stream_index == _audioStreamIndex){
            NSData *audio = [self.audioDecoderCtx decodeAudio:_pkt];
            av_packet_unref(_pkt);
            return audio;
        }
        av_packet_unref(_pkt);
        if (ret < 0){
            break;
        }
    }
    return NULL;
}
- (int) getBestVideoStream{
    printf("Fetching best stream");
    int ret = av_find_best_stream(_av_format, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (ret <0){
        const char *cfilename=[_url UTF8String];
        fprintf(stderr, "Could not find %s stream in input file '%s'\n",
                av_get_media_type_string(AVMEDIA_TYPE_VIDEO), cfilename);
        return -1;
    }
    _videoStreamIndex = ret;
    printf("Video index: %d\n",_videoStreamIndex);
    const SingleStreamInfo * info =  &_streamInfo[_videoStreamIndex];
    printf("Video Dims (%d x %d)\n",info->video_width,info->video_height);
    
    return _videoStreamIndex;
}
- (int) getBestAudioStream{
    int ret = av_find_best_stream(_av_format, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (ret <0){
        const char *cfilename=[_url UTF8String];
        fprintf(stderr, "Could not find %s stream in input file '%s'\n",
                av_get_media_type_string(AVMEDIA_TYPE_AUDIO), cfilename);
        return -1;
    }
    
    _audioStreamIndex = ret;
    
    const SingleStreamInfo * info =  &_streamInfo[_audioStreamIndex];
    printf("Audio index: %d\n",_audioStreamIndex);
    printf("Audio Sample Rate: %d\n,Channels: %d\n",info->audio_sample_rate,info->audio_nb_channels);
    
    return _audioStreamIndex;
}

-(int) initializeVideoCodec:(int) videoStreamId{
    int ret = -1;
    VideoCtx *context = [[VideoCtx alloc] init];
    ret = [context initCtx:_av_format secondValue:videoStreamId];
    _videoDecoderCtx = context;
    
    if (ret<0){
        printf("Could not initialize Video Decoder\n");
    }
    NSLog(@"Successfully initialized video codec");
    
    
    return ret;
}

-(int) initializeAudioCodec:(int) audioStreamId{
    int ret = -1;
    AudioCtx *context = [[AudioCtx alloc] init];
    ret = [context initCtx:_av_format secondValue:audioStreamId];
    _audioDecoderCtx = context;
    
    if (ret<0){
        printf("Could not initialize Audio Decoder\n");
    }
    NSLog(@"Successfully initialized audio codec");
    
    return ret;
}

- (SingleStreamInfo const * _Nullable) getStreamInfo:(int) streamId{
    
    if (_filled <= streamId){
        return NULL;
    }
    return &_streamInfo[streamId];
}
- (void) dealloc{
    
    // close the format decoder
    if (_av_format!=NULL){
        avformat_close_input(&_av_format);
    }
    if (_streamInfo != NULL){
        // close the stream info
        free(_streamInfo);
    }
    
    
}
@end
