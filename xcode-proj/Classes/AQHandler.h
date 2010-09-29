/*  AQHandler.h/.c - AudioQueue handler
 *  jamesghurley<at>gmail.com
 * 
 */

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioQueue.h>
#include "video_inst.h"

#define NUM_BUFFERS 3
#define BUFFER_DURATION 3

typedef struct {
	AudioStreamBasicDescription format;
	AudioQueueRef				queue;
	AudioQueueBufferRef			buffers[NUM_BUFFERS];
	AudioFileID					audioFile;
	SInt64						currentPacket;
	bool						playing;

	
} PlayState;
@interface AQHandler : NSObject {
	PlayState playState;

    SInt64                  pauseStart;

}
- (BOOL) isPlaying;
- (id) initWithAVDetails: (video_data_t*) av;

- (void) startPlayback;
- (UInt64) GetStartTime;
- (Float64) GetCurrentTime;
- (void) pausePlayback;
- (void) stopPlayback;
- (void) disposeQueue;
- (void) clearBuffers;

@end
