/*
 *  video_inst.h/.c - Video parse and decode instance. 
 *  Written by jamesghurley<at>gmail.com
 *  Uses FFMpeg statically so this is all LGPL.
 */

#ifndef __VIDEO_INST_H
#define __VIDEO_INST_H

#ifdef DEBUG

#define L1
//#define L2
//#define L3

#ifdef L1
#define PMSG1(...)      printf(__VA_ARGS__)
#else  // ?L1
#define PMSG1(...)
#endif // !L1

#ifdef L2
#define PMSG2(...)      printf(__VA_ARGS__)
#else // ?L2
#define PMSG2(...)
#endif // !L2

#ifdef L3
#define PMSG3(...)      printf(__VA_ARGS__)
#else // ?L3
#define PMSG3(...)
#endif // !L3

#else  // ?DEBUG

#define PMSG1(...)
#define PMSG2(...)
#define PMSG3(...)

#endif // !DEBUG

#ifdef __GNUC__ // Help gcc branch predicition
#ifndef likely
#define likely(x)       __builtin_expect(!!(x),1)
#endif // !likely

#ifndef unlikely
#define unlikely(x)     __builtin_expect(!!(x),0)
#endif // !unlikely

#else // ?__GNUC__

#ifndef likely
#define likely(x)       (x)
#endif // !likely

#ifndef unlikely
#define unlikely(x)     (x)
#endif // !unlikely

#endif // !__GNUC__

#ifndef next_powerof2
#define next_powerof2(x) \
x--;\
x |= x >> 1;\
x |= x >> 2;\
x |= x >> 4;\
x |= x >> 8;\
x |= x >> 16;\
x++;
#endif // !next_powerof2

typedef struct {
    struct video_context_t *context;
    struct {
		float fps_num;
		float fps_den;
		float duration;
		int	  bitrate;
		float time_base;
		int   frame_width;
		int   frame_height;
	} video;
	struct {
		int	  has_audio;
		int   format_id;
		int   sample_rate;
		int   format_flags;
		int   bytes_per_packet;
		int   channels_per_frame;
		int   frames_per_packet;
		int   bits_per_channel;
		int   bytes_per_frame;
		int   bitrate;
		int   frame_size;
		float time_base;
	} audio;    
} video_data_t;

void setupPlayer();

// Returns a pointer to a video_data_t structure if successful, NULL on failure.
video_data_t *openMovie(const char *fileName);

void closeMovie(video_data_t* vInst);
void seekToTime(video_data_t* vInst, unsigned int timeInSeconds);
void* getNextFrame(video_data_t* vInst, int* isDone, int* pts);
int getNextAudio(video_data_t* vInst, int maxlength, uint8_t* buf, int* pts, int* isDone);

void bufferCheck(video_data_t* vInst, int *videoBufferCount, int* videoBufferTotal, int *audioBufferCount, int *audioBufferTotal) ;

#endif // __VIDEO_INST_H