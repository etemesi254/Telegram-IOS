#import <FFMpegBinding/FFMpegHlsDecoder.h>

#import "libavcodec/avcodec.h"
#import "libavformat/avformat.h"
#include "libavutil/timestamp.h"
#include "libavutil/imgutils.h"


static enum AVPixelFormat get_hw_format(AVCodecContext *ctx,
                                        const enum AVPixelFormat *pix_fmts)
{
    const enum AVPixelFormat *p;
    
    for (p = pix_fmts; *p != -1; p++) {
        if (*p == AV_PIX_FMT_VIDEOTOOLBOX)
            // match for videotoolbox which offers H/W decoding
            return *p;
    }
    
    fprintf(stderr, "Failed to get HW surface format.\n");
    // fall back to software
    return *pix_fmts;
}

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
    
    return 0;
}
- (int) decodeAudio:(AVPacket * _Nullable) pkt secondValue:(HlsOutputData * _Nullable)output{
    int ret = 0;
    // submit the packet to the decoder
    ret = avcodec_send_packet(_ctx.ctx, pkt);
    if (ret < 0) {
        fprintf(stderr, "Error submitting a packet for decoding (%s)\n", av_err2str(ret));
        return ret;
    }
    
    // get all the available frames from the decoder
    while (ret >= 0) {
        ret = avcodec_receive_frame(_ctx.ctx, _ctx.frame);
        if (ret < 0) {
            // TODO: Handle way of calling multiple avcodec_recieve_frame
            // using the bugs bunny test i think, we fail on first sample because we
            // don't call avcodec_recieve_frame multiple times, if it fails we return more.
            
            // those two return values are special and mean there is no output
            // frame available, but there were no errors during decoding
            if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN)){
                return ret;
            }
            
            fprintf(stderr, "Error during decoding (%s)\n", av_err2str(ret));
            return ret;
        }
        
        // confirm we are decoding audio
        assert(_ctx.ctx->codec->type==AVMEDIA_TYPE_AUDIO &&
               "A codec that is not audio sent to audio decoder");
        
        AVFrame *frame = _ctx.frame;
        if (DEBUG){
            printf("audio_frame n:%d nb_samples:%d pts:%s\n",
                   _frameNo++, frame->nb_samples,
                   av_ts2timestr(frame->pts,&_ctx.ctx->time_base));
        }
        ret = [self convertFrameToPCM: output];
        
        return ret;
    }
    
    return ret;
}
- (int ) convertFrameToPCM:(HlsOutputData * _Nullable) output{
    
    // TODO: Handle complex format not supported by audio output.
    // Thinking of double and such, AVAudio cannot play them
    
    if (output==NULL){
        if (DEBUG){
            fprintf(stderr,"Output sent to PCM is nil!!");
        }
        return -1;
    }
    
    if (DEBUG){
        NSLog(@"Converting Frame to PCM\n");
    }
    
    int channelCount = _ctx.ctx->ch_layout.nb_channels;
    int bytesPerSample = av_get_bytes_per_sample(_ctx.ctx->sample_fmt);
    
    output.streamType = 0; //indicate stream is audio
    
    int singleChannelSize = _ctx.frame->nb_samples * bytesPerSample;
    int dataSize = singleChannelSize*channelCount;
    if (output.audioData == nil){
        output.audioData = [NSMutableData dataWithLength:dataSize + 12 /*good luck charm*/];
    }
    // allocate if size is too small
    if (output.audioData.length < dataSize){
        output.audioData = [NSMutableData dataWithLength:dataSize + 12 /*good luck charm*/];
        
    }
    assert(output.audioData.length>=dataSize && "Too small audio buffer");
    
    
    uint8_t *pcmBuffer = (uint8_t *)output.audioData.mutableBytes;
    
    
    // Handle planar and packed formats
    if (av_sample_fmt_is_planar(_ctx.ctx->sample_fmt)) {
        // PLANNAR FORMAT
        // Pack it in the following format
        // LLLLL...LL, RRRRRRR
        // Since the AVAudio does not support interleaved data for some reason
        // Planar format (e.g., AV_SAMPLE_FMT_S16P)
        for (int ch = 0; ch < channelCount; ch++) {
            memcpy(pcmBuffer, _ctx.frame->data[ch], singleChannelSize);
            pcmBuffer+=singleChannelSize;
        }
    } else {
        // Packed format (e.g., AV_SAMPLE_FMT_S16)
        // TODO: Packed format may be a problem e.g what if it's LRLRLRLRLRL?? (should be separated)
        // Look into it.
        memcpy(pcmBuffer, _ctx.frame->data[0], singleChannelSize);
    }
    return 0;
    
}


@end

@implementation VideoCtx

- (int) initCtx:(AVFormatContext *)ctx secondValue:(int)streamId{
    SingleCtx *context = [[SingleCtx alloc] init];
    [context initializeContext: ctx secondValue:streamId thirdValue:true];
    _ctx = context;
    
    
    _hwDecodingAvailable=false;
    if ([self initHwDecoder:ctx secondValue:streamId] < 0){
        NSLog(@"Could not initialize hardware decoder, using software decoder");
        _hwDecodingAvailable=false;
    } else{
        NSLog(@"Hardware decoder successfully initialized, using it for decoding");
        _hwDecodingAvailable=true;
    }
    return 0;
}
- (int) decodeVideo:(AVPacket * _Nullable) pkt secondValue:(HlsOutputData * _Nullable)output{
    int ret = 0;
    
    // submit the packet to the decoder
    ret = avcodec_send_packet(_ctx.ctx, pkt);
    if (ret < 0) {
        fprintf(stderr, "Error submitting a packet for decoding (%s)\n", av_err2str(ret));
        return ret;
    }
    
    AVFrame *sw_frame = NULL;
    AVFrame *tmp_frame = NULL;
    
    // get all the available frames from the decoder
    while (ret >= 0) {
        ret = avcodec_receive_frame(_ctx.ctx, _ctx.frame);
        if (ret < 0) {
            // TODO: Handle way of calling multiple avcodec_recieve_frame
            // using the bugs bunny test i think, we fail on first sample because we
            // don't call avcodec_recieve_frame multiple times, if it fails we return more.
            
            // those two return values are special and mean there is no output
            // frame available, but there were no errors during decoding
            if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN)){
                return ret;
            }
            
            fprintf(stderr, "Error during decoding (%s)\n", av_err2str(ret));
            return ret;
        }
        
        // confirm we are decoding video
        assert(_ctx.ctx->codec->type==AVMEDIA_TYPE_VIDEO &&
               "A codec that is not video sent to video decoder");
        if (_ctx.frame->format == AV_PIX_FMT_VIDEOTOOLBOX ){
            // retrieve data from gpu to cpu
            if ((ret = av_hwframe_transfer_data(sw_frame, _ctx.frame, 0)) < 0) {
                fprintf(stderr, "Error transferring the data to system memory\n");
                return ret;
            }
            tmp_frame = sw_frame;
        } else{
            tmp_frame = _ctx.frame;
        }
        
        int size = av_image_get_buffer_size(tmp_frame->format,tmp_frame->width,tmp_frame->height,1);
        if (output.videoData == nil){
            HlsVideoData *temp = [[HlsVideoData alloc] init];
            output.videoData = temp;
            
            output.videoData.data = [NSMutableData dataWithLength:size + 12 /*good luck charm*/];
        }
        // allocate if size is too small
        if (output.videoData.data.length < size){
            output.videoData.data = [NSMutableData dataWithLength:size + 12 /*good luck charm*/];
        }
        output.videoData.width = _ctx.frame->width;
        output.videoData.height = _ctx.frame->height;
        
        int ret = av_image_copy_to_buffer((uint8_t *) output.videoData.data.mutableBytes, size,
                                          (const uint8_t * const *)tmp_frame->data,
                                          (const int *)tmp_frame->linesize,
                                          tmp_frame->format, tmp_frame->width,tmp_frame->height, 1);
        
        if (ret < 0){
            fprintf(stderr, "Can not copy image to buffer\n");
        }
        
    }
    
    return ret;
}
- (void) dealloc {
    if (_hwBufferRef){
        av_buffer_unref(&_hwBufferRef);
    }
}
- (int)initHwDecoder:(AVFormatContext * _Nonnull)fmtCtx secondValue:(int)streamId {
    // Example : https://ffmpeg.org/doxygen/trunk/hw__decode_8c_source.html
    
    // find videotoolboox
    enum AVHWDeviceType videoToolBox = av_hwdevice_find_type_by_name("videotoolbox");
    AVStream *st = fmtCtx->streams[streamId];
    const AVCodec *dec = avcodec_find_decoder(st->codecpar->codec_id);
    
    for (int i = 0;; i++) {
        const AVCodecHWConfig *config = avcodec_get_hw_config(dec, i);
        if (!config) {
            fprintf(stderr, "Decoder %s does not support device type %s.\n",
                    dec->name, av_hwdevice_get_type_name(videoToolBox));
            return -1;
        }
        if (config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX &&
            config->device_type == videoToolBox) {
            break;
        }
    }
    if (avcodec_parameters_to_context(_ctx.ctx, st->codecpar)< 0){
        NSLog(@"Parameters to context failed");
        return -1;
    }
    // initialize decoder
    _ctx.ctx->get_format = get_hw_format;
    int err = 0;
    if ((err=av_hwdevice_ctx_create(&_hwBufferRef, videoToolBox
                                    , NULL,NULL, 0))<0){
        NSLog(@"Failed to create specified HW Device\n");
        return  err;
    }
    _ctx.ctx->hw_device_ctx = av_buffer_ref(_hwBufferRef);
    
    // BUG: We called avcodec_open2 before, will this work?
    if ((err = avcodec_open2(_ctx.ctx, dec, NULL)) < 0) {
        NSLog(@"Failed to open codec for stream");
        return -1;
    }
    return err;
}

@end


@implementation FFmpegHLSDecoder

- (void) init:(NSString *)url{
    if (DEBUG){
        NSLog(@"Calling Init ");
    }
    _url =url;
    _videoStreamIndex = -1;
    _audioStreamIndex = -1;
    _shouldDecodeAudio=true;
    _shouldDecodeVideo=true;
    
    _pkt = av_packet_alloc();
    if (!_pkt) {
        fprintf(stderr, "Could not allocate packet\n");
    }
    _output = [[HlsOutputData alloc] init];
    putenv("AV_LOG_FORCE_NOCOLOR=1");
    
    //    if (DEBUG){
    //        av_log_set_level(AV_LOG_DEBUG);
    //    }
}
// tutorial https://github.com/Golim4r/OpenGL-Video-Player/blob/master/src/Decoder.cpp

- (int) readData{
    
    if (_url==nil){
        if (DEBUG){
            NSLog(@"URL not initialized, call init()!!!");
        }
        return -1;
    }
    
    if (DEBUG){
        NSLog(@"Reading HLS Stream");
    }
    // https://ffmpeg.org/doxygen/5.1/demuxing_decoding_8c-example.html#_a0
    AVFormatContext *fmt_ctx = NULL;
    
    const char *cfilename=[_url UTF8String];
    if (DEBUG){
        printf("Filename: %s\n",cfilename);
    }
    int ret = avformat_open_input(&fmt_ctx, cfilename, NULL, NULL);
    /* open input file, and allocate format context */
    if (ret<0) {
        fprintf(stderr, "cannot open file %s\n",av_err2str(ret));
        return ret;
    }
    _avFmtCtx=fmt_ctx;
    
    
    /* retrieve stream information */
    if (avformat_find_stream_info(fmt_ctx, NULL) < 0) {
        ret = -1;
        fprintf(stderr, "Could not find stream information\n");
        return ret ;
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
    if ((ret = [self getBestVideoStream]) < 0){
        return ret;
    }
    if ((ret = [self getBestAudioStream]) < 0){
        return ret;
    }
    // initialize audio and video codecs
    if ((ret= [self initializeVideoCodec:(int)_videoStreamIndex])< 0){
        return ret;
    }
    if ((ret=[self initializeAudioCodec:(int)_audioStreamIndex]) < 0){
        return ret;
    }
    return ret;
    
}
- (int) setVideoDecoder:(int)videoStreamId{
    // first check if stream id exists
    if (videoStreamId > _avFmtCtx->nb_streams){
        NSLog(@"Video Stream index larger than available stream");
        return -1;
    }
    // then confirm that stream id is a video
    AVStream *st = _avFmtCtx->streams[videoStreamId];
    if (st->codecpar->codec_type!=AVMEDIA_TYPE_VIDEO){
        NSLog(@"Video Stream index not a video stream");
        return -1;
    }
    // okay works.
    _videoStreamIndex = videoStreamId;
    
    // initialize the codec
    return [self initializeVideoCodec:(int)_videoStreamIndex];
    // TODO: should we seek to the new position?? or is it done automatically
}
- (HlsOutputData * _Nullable) decode{
    if (DEBUG){
        printf("Starting decoding\n");
    }
    int ret = 0;
    
    /* read frames from the file */
    while (av_read_frame(_avFmtCtx, _pkt) >= 0) {
        if (_pkt->stream_index == _audioStreamIndex){
            int ret = [self.audioDecoderCtx decodeAudio:_pkt secondValue:_output];
            
            if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN)){
                continue;
            }
            av_packet_unref(_pkt);
            
            if (ret >=0){
                return _output;
            } else{
                return NULL;
            }
        }
        if (_pkt->stream_index == _videoStreamIndex){
            int ret = [self.videoDecoderCtx decodeVideo:_pkt secondValue:_output];
            if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN)){
                continue;
            }
            av_packet_unref(_pkt);
            
            if (ret >=0){
                return _output;
            } else{
                return NULL;
            }
        }
        av_packet_unref(_pkt);
        if (ret < 0){
            break;
        }
    }
    return NULL;
    
}
- (int) getBestVideoStream{
    int ret = av_find_best_stream(_avFmtCtx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (ret <0){
        const char *cfilename=[_url UTF8String];
        fprintf(stderr, "Could not find %s stream in input file '%s'\n",
                av_get_media_type_string(AVMEDIA_TYPE_VIDEO), cfilename);
        return -1;
    }
    _videoStreamIndex = ret;
    const SingleStreamInfo * info =  &_streamInfo[_videoStreamIndex];
    
    if (DEBUG){
        printf("Video index: %d\n",_videoStreamIndex);
        printf("Video Dims (%d x %d)\n",info->video_width,info->video_height);
    }
    
    return _videoStreamIndex;
}
- (int) getBestAudioStream{
    
    int ret = av_find_best_stream(_avFmtCtx, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (ret < 0){
        const char *cfilename=[_url UTF8String];
        fprintf(stderr, "Could not find %s stream in input file '%s'\n",
                av_get_media_type_string(AVMEDIA_TYPE_AUDIO), cfilename);
        return ret;
    }
    
    _audioStreamIndex = ret;
    
    const SingleStreamInfo * info =  &_streamInfo[_audioStreamIndex];
    
    if (DEBUG){
        printf("Audio index: %d\n",_audioStreamIndex);
        printf("Audio Sample Rate: %d\n,Channels: %d\n",info->audio_sample_rate,info->audio_nb_channels);
    }
    
    return _audioStreamIndex;
}

-(int) initializeVideoCodec:(int) videoStreamId{
    int ret = -1;
    VideoCtx *context = [[VideoCtx alloc] init];
    ret = [context initCtx:_avFmtCtx secondValue:videoStreamId];
    _videoDecoderCtx = context;
    
    
    if (ret<0){
        if (DEBUG){
            printf("Could not initialize Video Decoder\n");
        }
    } else{
        if (DEBUG){
            NSLog(@"Successfully initialized video codec");
        }
    }
    return ret;
}

-(int) initializeAudioCodec:(int) audioStreamId{
    int ret = -1;
    AudioCtx *context = [[AudioCtx alloc] init];
    ret = [context initCtx:_avFmtCtx secondValue:audioStreamId];
    _audioDecoderCtx = context;
    
    
    if (ret<0){
        if  (DEBUG){
            NSLog(@"Could not initialize Audio Decoder\n");
        }
    } else{
        if (DEBUG){
            NSLog(@"Successfully initialized Audio Decoder");
        }
    }
    return ret;
}

- (SingleStreamInfo const * _Nullable) getStreamInfo:(int) streamId{
    
    if (_filled <= streamId){
        return NULL;
    }
    return &_streamInfo[streamId];
}
- (int) seekTo:(double)timeStamp{
    // seek both video and audio
    int ret = 0;
    if ((ret=av_seek_frame(_avFmtCtx, _videoStreamIndex, (int)timeStamp,0)) <0){
        return ret;
    }
    if ((ret=av_seek_frame(_avFmtCtx, _audioStreamIndex, (int)timeStamp,0)) <0){
        return ret;
    }
    return ret;
    
}
- (void) dealloc{
    
    // close the format decoder
    if (_avFmtCtx!=NULL){
        avformat_close_input(&_avFmtCtx);
    }
    if (_streamInfo != NULL){
        // close the stream info
        free(_streamInfo);
    }
}

@end
