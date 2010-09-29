/*
 *  MoviePlayerController.h/.m - Handles movie playback state.
 *  jamesghurley<at>gmail.com
 */
#import <Foundation/Foundation.h>
#import "ESRenderer.h"
#import "AQHandler.h"
#import "video_inst.h"
#import <pthread.h>

// State structure to be passed to the decode thread.
typedef struct  {
    video_data_t * pVideoInst;
    AQHandler    * pAqInst;
    BOOL           moviePlaying;
    BOOL           killThread;
    BOOL           movieOpen;
    BOOL           movieFinished;
    BOOL           frameReady;
    pthread_t      thread;
    long           currentPTS;
    uint8_t      * pOutBuffer;
    pthread_mutex_t frameMutex;
} state_data_t;


@interface MoviePlayerController : NSObject<MoviePlayerStateNotify> {
@private
    id<ESRenderer> renderer;
    state_data_t stateInst;
    uint mWidth, mHeight, texW, texH;
    BOOL useES1; 
}
@property (readonly) BOOL useES1;
- (void) render;
- (BOOL) resizeFromLayer:(CAEAGLLayer *)layer;

- (id) init;

- (int) play;
- (int) stop;
- (int) pause;
- (int) loadVideoFile:(const char *)file;
- (int) seekToTime: (int) timeInSeconds;

- (int64_t) getMovieTimeInSeconds;
- (int64_t) getMovieDurationInSeconds;

- (BOOL) movieIsPlaying;
- (BOOL) movieIsLoaded;
- (BOOL) movieIsFinished;

- (void) closeMovie;
- (void) nextStereoMode;

@end
