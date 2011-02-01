/*
 *  video_inst.h/.c - Video parse and decode instance. 
 *  Written by jamesghurley<at>gmail.com
 *  Uses FFmpeg statically so this is all LGPL.
 */

#include <pthread.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libavutil/mathematics.h"
#include "libavcodec/avcodec.h"
#include "libswscale/swscale.h"

#include "mach_util.h"
#include "video_inst.h"

#define STATE_NOMO 0x0  // No movie loaded
#define STATE_STOP 0x1  // Movie loaded but not playing 
#define STATE_PLAY 0x2  // Movie playing 
#define STATE_PAUS 0x3  // Movie paused
#define STATE_EOF  0x4  // Parser reached EOF; movie could be in a different play state.
#define STATE_DIE  0x8  // Everything should die.

#define ABUF_SIZE  512
#define VBUF_SIZE  512

enum {
	kUnlocked = 0,
	kLocked = 1
};


struct ring {
    unsigned long read, write, count ; 
    unsigned short lock;
} ;

// Opaque context
struct video_context_t {
    uint8_t             play_state;
    
    AVFormatContext     *p_format_ctx;
    AVCodecContext      *p_video_ctx, *p_audio_ctx;
	
    AVPacket            packet;
    AVFrame             *p_picture, *p_picture_rgb;
    AVPacket            audio_buffer[ABUF_SIZE];
    AVPacket            video_buffer[VBUF_SIZE];
    AVCodec             *p_codec;
    uint8_t             *p_frame_buffer;
    
    pthread_t           decode_thread;
    struct SwsContext   *p_sws_ctx;
    
    long                seek_req;
    struct ring         audio_ring, video_ring;
    int                 idx_video_stream, idx_audio_stream;
};

static short s_didSetupPlayer = 0 ;

static inline void drainBuffers(video_data_t *v) {
    int i ;
    struct video_context_t *c = v->context;
    
    c->audio_ring.lock = kLocked;
    c->video_ring.lock = kLocked;
    
    for (i = 0 ; i < ABUF_SIZE ; i ++){
        if(c->audio_buffer[i].data)
        {
            free(c->audio_buffer[i].data);
            c->audio_buffer[i].size = 0;
            c->audio_buffer[i].data = 0L;
            
        }
    }
    for(i = 0; i < VBUF_SIZE ; i ++){
        if(c->video_buffer[i].data)
        {
            free(c->video_buffer[i].data);
            c->video_buffer[i].size = 0;
            c->video_buffer[i].data = 0L;
            
        }
    }
    
    c->audio_ring.read = 0;
    c->video_ring.read = 0;
    c->video_ring.write = 0;
    c->audio_ring.write = 0;
    c->audio_ring.count = 0;
    c->video_ring.count = 0;
    c->audio_ring.lock = kUnlocked;
    c->video_ring.lock = kUnlocked;
}

/*
 *  void* parseThread(void*)
 *  Parses through movie, buffering audio and video packets
 *
 */
void *parseThread(void *data){
    long                    len;
    struct ring *           r;
    int                     limit;
    video_data_t *          v = (video_data_t*)data;
    struct video_context_t *c = v->context;
    AVPacket*               pkt;
        
    PMSG3("\n\rvideo_inst.c::parseThread: Parse Thread Started.\n");
    
    
    // Parse loop
    while(likely(!(c->play_state & STATE_DIE)))
    {
        if(unlikely(c->seek_req > 0)){
            // Received a request to seek
            drainBuffers(v);
            av_seek_frame(c->p_format_ctx, -1, c->seek_req * AV_TIME_BASE, 0); // Seek to the appropriate time
            c->seek_req = 0;
            c->play_state ^= (c->play_state & STATE_EOF);  // If we've reached EOF, we aren't there any longer.
            continue;
        }
        if(unlikely((c->play_state & STATE_EOF) == STATE_EOF)){
            usleep(3000); // If we've reached EOF just continue to loop until the movie is closed or a seek is requested
            continue;
        }
        
        len = av_read_frame(c->p_format_ctx, &c->packet);   // Grab the next packet
        
        if ( unlikely(len < 0) ) {
            // If a negative number is returned, we've hit the EOF. Set the state and continue looping.
            c->play_state |= STATE_EOF;
            PMSG2("\n\rvideo_inst.c::parseThread: Parse thread reached EOF.\n\r");
            continue;
        }
        
        if(c->packet.stream_index == c->idx_video_stream){
            // Got a video packet
            while( (c->video_ring.lock ||  c->video_ring.count >= VBUF_SIZE) && !(c->play_state & STATE_DIE) && c->seek_req == 0) {
                usleep(50);
            }
            if(unlikely(c->seek_req > 0)) goto skip;
            if(unlikely((c->play_state & STATE_DIE) == STATE_DIE)) goto parse_thread_die;
            
            r = &c->video_ring;
            pkt = &c->video_buffer[r->write];
            limit = VBUF_SIZE;
        } 
        else if ( c->packet.stream_index == c->idx_audio_stream && v->audio.has_audio) {
            // Got an audio packet
            while( (c->audio_ring.lock ||  c->audio_ring.count >= ABUF_SIZE) && !(c->play_state & STATE_DIE) && c->seek_req == 0) {
                usleep(50);
            }
            if(unlikely(c->seek_req > 0)) goto skip;
            if(unlikely((c->play_state & STATE_DIE) == STATE_DIE)) goto parse_thread_die;
            
            r = &c->audio_ring;
            pkt = &c->audio_buffer[r->write];
            limit = ABUF_SIZE;
        }
        else goto skip; // Got an unsupported packet; skip this packet and free it.
        
        r->lock = kLocked;
        
        if(likely(pkt->data)){
            free(pkt->data);
            pkt->size=0;
            pkt->data=0L;
        }
        // Deep copy the packet into the buffer since the packet becomes invalidated next time 
        // av_read_frame is called.
        pkt->data           = (uint8_t*)calloc(1,c->packet.size);
		pkt->size           = c->packet.size;
		pkt->stream_index   = c->packet.stream_index;
		pkt->flags          = c->packet.flags;
		pkt->duration       = c->packet.duration;
		pkt->pos            = c->packet.pos;
		pkt->convergence_duration = c->packet.convergence_duration;
		pkt->pts            = c->packet.pts;
		pkt->dts            = c->packet.dts;
		pkt->destruct       = c->packet.destruct;
		pkt->priv           = &c->video_buffer[c->video_ring.write];
        
		memcpy(pkt->data, c->packet.data, c->packet.size);
        r->write++;
		r->count++;
		if(unlikely(r->write >= limit)) r->write %= limit;
		
		r->lock = kUnlocked;
    skip:
        av_free_packet(&c->packet); // Free the packet.
        
    }
    
    pthread_exit(NULL);
parse_thread_die:
    PMSG2("\n\rvideo_inst.c::parseThread: parse_thread_die reached.\n\r");
    av_free_packet(&c->packet);
    pthread_exit(NULL);
}
/**************************************************************************
    Public Functions
/*************************************************************************/
/*
 *  Setup AVCodec.
 */
void setupPlayer(){
    if(!s_didSetupPlayer){
        s_didSetupPlayer=1;
        avcodec_init();
        av_register_all();

    }
}

// Returns a pointer to a video_data_t structure if successful, NULL on failure.
// Open a movie file.
video_data_t *openMovie(const char *fileName){
    int           i;
    int           err;
    
    video_data_t*           vdata ;
    struct video_context_t* ctx ;
    
    if(!s_didSetupPlayer)
        setupPlayer();
    
    if(!fileName)
        return NULL;
    
    // Allocate our video data instances
    vdata          = calloc(1,sizeof(video_data_t));
    vdata->context = calloc(1,sizeof(struct video_context_t));
    
    ctx = vdata->context;
    
    ctx->idx_video_stream = -1;
    ctx->idx_audio_stream = -1;
    ctx->seek_req = 0;
    err = av_open_input_file(&ctx->p_format_ctx, fileName, NULL, 0, NULL);
    if(err != 0){
        PMSG1("\n\rvideo_inst.c::openMovie failed to open input file: %s\n", fileName);
        free(vdata->context);
        free(vdata);
        return NULL;
    }
    
    err = av_find_stream_info(ctx->p_format_ctx);
    if(err < 0){
        PMSG1("\n\rvideo_inst.c::openMovie failed to find stream info.\n");
        free(vdata->context);
        free(vdata);
        return NULL;
    }
    
#ifdef DEBUG 
    dump_format(ctx->p_format_ctx, 0, fileName, 0);
#endif
    // Only supporting audio and video for this demo.
    for(i = 0 ; i < ctx->p_format_ctx->nb_streams ; i ++) {
        if(ctx->p_format_ctx->streams[i]->codec->codec_type == CODEC_TYPE_VIDEO)
            ctx->idx_video_stream = i;
        if(ctx->p_format_ctx->streams[i]->codec->codec_type == CODEC_TYPE_AUDIO)
            ctx->idx_audio_stream = i;
    }
    
    if(ctx->idx_video_stream < 0){
        PMSG1("\n\rvideo_inst.c::openMovie failed to find a video stream.\n");
        av_close_input_file(ctx->p_format_ctx);
        free(vdata->context);
        free(vdata);
        return NULL;
    }
    if(ctx->idx_audio_stream >= 0){
        vdata->audio.has_audio = 1;
    }
#ifdef DEBUG
    else {
        PMSG1("\n\rvideo_inst.c::openMovie failed to find audio stream.\n");
    }
#ifdef DISABLE_AUDIO
    vdata->audio.has_audio = 0;
#endif // DISABLE_AUDIO
#endif // DEBUG
    
    ctx->p_picture_rgb = avcodec_alloc_frame();
    ctx->p_picture     = avcodec_alloc_frame(); 
    ctx->p_video_ctx   = ctx->p_format_ctx->streams[ctx->idx_video_stream]->codec;
    ctx->p_audio_ctx   = ctx->p_format_ctx->streams[ctx->idx_audio_stream]->codec;
    
    PMSG2("\n\rvideo.c loadMovie: Frame rate: %lf\n\r", (float)ctx->p_format_ctx->streams[ctx->idx_video_stream]->r_frame_rate.num / (float)ctx->p_format_ctx->streams[ctx->idx_video_stream]->r_frame_rate.den);
    vdata->video.fps_den                       = (float)ctx->p_format_ctx->streams[ctx->idx_video_stream]->r_frame_rate.den;
    vdata->video.fps_num                       = (float)ctx->p_format_ctx->streams[ctx->idx_video_stream]->r_frame_rate.num;
    vdata->video.duration                      = ctx->p_format_ctx->streams[ctx->idx_video_stream]->duration;
    vdata->video.time_base                     = (float)ctx->p_format_ctx->streams[ctx->idx_video_stream]->r_frame_rate.den / (float)ctx->p_format_ctx->streams[ctx->idx_video_stream]->r_frame_rate.num;
    vdata->video.frame_width                   = ctx->p_video_ctx->width;
    vdata->video.frame_height                  = ctx->p_video_ctx->height;
	
	if(vdata->audio.has_audio){
        
        vdata->audio.sample_rate           = ctx->p_audio_ctx->sample_rate;
        vdata->audio.format_id             = ctx->p_audio_ctx->codec_id;
        vdata->audio.bytes_per_packet      = ctx->p_audio_ctx->frame_size/16;
        vdata->audio.frames_per_packet     = 1;
        vdata->audio.channels_per_frame    = ctx->p_audio_ctx->channels;
        vdata->audio.bytes_per_frame       = ctx->p_audio_ctx->frame_size/16;
        vdata->audio.bitrate               = ctx->p_audio_ctx->bit_rate;
        vdata->audio.frame_size            = ctx->p_audio_ctx->frame_size;
        vdata->audio.time_base             = (float)ctx->p_format_ctx->streams[ctx->idx_audio_stream]->time_base.num / (float)ctx->p_format_ctx->streams[ctx->idx_audio_stream]->time_base.den;        
	}
    ctx->p_codec = avcodec_find_decoder(ctx->p_video_ctx->codec_id); // Get the appropriate decoder for the video format [MPEG4v2 decodes fastest in software on the iPhone]
    
    if(avcodec_open(ctx->p_video_ctx,ctx->p_codec)<0){
        PMSG1("\n\rvideo_inst.c::openMovie failed to open the appropriate codec.\n");
        av_close_input_file(ctx->p_format_ctx);
        av_free(ctx->p_picture);
        av_free(ctx->p_picture_rgb);
        free(vdata->context);
        free(vdata);
        return NULL;
    }
    
    // We're going to use SWScale for YCbCr4:2:0->RGB565LE conversion.  
    // This could be done in a fragment shader, but we're supporting both OpenGLES1.1 and OpenGLES2.0. 
    // Doing colorspace conversion with glColorMask and clever blending gives less impressive results
    // with only a minor performance boost.  The real bottleneck on slower devices is texture upload.
    //
    // Any actual scaling WILL reduce performance massively.
    ctx->p_sws_ctx = sws_getContext(ctx->p_video_ctx->width, 
                                    ctx->p_video_ctx->height, 
                                    ctx->p_video_ctx->pix_fmt, 
                                    ctx->p_video_ctx->width, 
                                    ctx->p_video_ctx->height,
                                    PIX_FMT_RGB565, SWS_FAST_BILINEAR, NULL, NULL, NULL);
    
    // Framebuffer for RGB data
    ctx->p_frame_buffer = malloc(avpicture_get_size(PIX_FMT_RGB565,
                                                    ctx->p_video_ctx->width, 
                                                    ctx->p_video_ctx->height));
    
    avpicture_fill((AVPicture*)ctx->p_picture_rgb, ctx->p_frame_buffer, PIX_FMT_RGB565, 
                   ctx->p_video_ctx->width, 
                   ctx->p_video_ctx->height);
    
    ctx->play_state |= STATE_PLAY;
    
    pthread_create(&ctx->decode_thread, NULL, parseThread, (void*)vdata);
    
    return vdata;
}

// Close the movie and end the parse thread.
//
void  closeMovie  (video_data_t* vInst) {
    vInst->context->play_state |= STATE_DIE;
    usleep(10000);
    av_close_input_file(vInst->context->p_format_ctx);
    av_free(vInst->context->p_picture_rgb);
    av_free(vInst->context->p_picture);
    drainBuffers(vInst);
    free(vInst->context->p_frame_buffer);
    free(vInst->context);
    free(vInst);
    vInst = 0L;
}
// Signal that we want to seek to a particular time
void  seekToTime  (video_data_t* vInst, unsigned int timeInSeconds) {
    vInst->context->seek_req = timeInSeconds;
}

// Decode the next available video frame
void* getNextFrame(video_data_t* vInst,  int* isDone, int* pts){
	
    int got_picture = 0;
    int bytes = 0;
    int count= 0;
    struct video_context_t *ctx = vInst->context;
    
    while(!got_picture && ctx->video_ring.count > 0){
        // Loop until the picture has been decoded entirely.
        while((ctx->video_ring.lock) && ((ctx->play_state & STATE_DIE) != STATE_DIE)){
			usleep(100);
		}
        ctx->video_ring.lock = kLocked;
        bytes = ctx->p_video_ctx->codec->decode(ctx->p_video_ctx, ctx->p_picture, &got_picture, (AVPacket*)&ctx->video_buffer[ctx->video_ring.read]);
        if(!count) // use the first presentation timestamp as the frame pts.
            *pts = ctx->video_buffer[ctx->video_ring.read].pts;
        count++;
        ctx->video_ring.read++;
        ctx->video_ring.count--;
        ctx->video_ring.read%=VBUF_SIZE;
        ctx->video_ring.lock=kUnlocked;
    }
   
    if(likely(got_picture))
        sws_scale(ctx->p_sws_ctx, ctx->p_picture->data,ctx->p_picture->linesize,0,ctx->p_video_ctx->height,ctx->p_picture_rgb->data,ctx->p_picture_rgb->linesize);
    
    if(unlikely((ctx->play_state & STATE_EOF) == STATE_EOF && ctx->video_ring.count == 0)){
        *isDone = 1;
        
    }
    return (void*)ctx->p_frame_buffer;
    
}

// Get encoded audio packets of a specified length (We are not decoding in software because AudioQueues can decode MP3 data in hardware)
int   getNextAudio(video_data_t* vInst, int maxlength, uint8_t* buf, int* pts, int* isDone) {
  
    struct video_context_t  *ctx = vInst->context;
    int    datalength            = 0;
    
    while(ctx->audio_ring.lock || (ctx->audio_ring.count <= 0 && ((ctx->play_state & STATE_DIE) != STATE_DIE))){
        usleep(100);
    }
    
    *pts = 0;
    ctx->audio_ring.lock = kLocked;
    
    if (ctx->audio_ring.count>0 && maxlength > ctx->audio_buffer[ctx->audio_ring.read].size) {
                
        memcpy(buf, ctx->audio_buffer[ctx->audio_ring.read].data, ctx->audio_buffer[ctx->audio_ring.read].size);
        
        *pts = ctx->audio_buffer[ctx->audio_ring.read].pts;
        
        datalength = ctx->audio_buffer[ctx->audio_ring.read].size;
        
        ctx->audio_ring.read++;
        
        ctx->audio_ring.read %= ABUF_SIZE;
        
        ctx->audio_ring.count--;
        
    }
	
    ctx->audio_ring.lock = kUnlocked;
    
    if((ctx->play_state & STATE_EOF) == STATE_EOF && ctx->audio_ring.count == 0) *isDone = 1;
    return datalength;
}

// Check buffer levels
void  bufferCheck (video_data_t* vInst, int *videoBufferCount, int* videoBufferTotal, int *audioBufferCount, int *audioBufferTotal) {
    *videoBufferCount = vInst->context->video_ring.count;
	*audioBufferCount = vInst->context->audio_ring.count;
	*audioBufferTotal = ABUF_SIZE;
	*videoBufferTotal = VBUF_SIZE;
}