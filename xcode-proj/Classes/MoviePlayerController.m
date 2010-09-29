/*
 *  MoviePlayerController.h/.m - Handles movie playback state.
 *  jamesghurley<at>gmail.com
 */
#import "MoviePlayerController.h"
#import "ES2Renderer.h"
#import "ES1Renderer.h"
#import "mach_util.h"
#import <unistd.h>

#define BYTES_PER_PIXEL 2

static void *runMovie(void *data) {
    
    state_data_t * pData = (state_data_t *)data;
    video_data_t * pVideo = pData->pVideoInst;
    uint8_t * buf;
    
	int sleepTime = 0;
	int isDone = 0;
	int pts=0;
    int startPts=-1;
    UInt64 ct, dt=0;
	UInt64 startTime = 1;
    
	// Video time base in Microseconds
	UInt64 timeBaseUs = (UInt64) (pVideo->video.time_base * 1.0e6f);
	
    startTime = mu_currentTimeInMicros();
    
	while(likely(isDone==0 && !pData->killThread)){
        
        
        // Sleep until we want to start playing again.
        
        while( unlikely(!pData->moviePlaying) ) {
            usleep(1000);
            if (pData->killThread) goto die;
        } 
        
	    buf = getNextFrame(pVideo, &isDone, &pts);
        
        if(startPts < 0) startPts = pts;
        pData->currentPTS = pts;
        
        pts-=startPts;
        
        dt = ((UInt64)pts * timeBaseUs) + startTime ;
        
        while (unlikely((ct =mu_currentTimeInMicros()) < dt ) ) 	
		{
			sleepTime = dt - ct;
			if(sleepTime < 0) sleepTime = 0;
			usleep(sleepTime);// dt - ct < 0 only when texture is locked or we're lagging
		}
        
        // The idea of having a secondary image buffer is so that we can start decoding the next frame
        // while OpenGL uploads the current frame to the texture without experiencing tearing.
        while(pData->frameReady == YES && !pData->killThread) usleep(50);
        memcpy(pData->pOutBuffer, buf, pVideo->video.frame_width * pVideo->video.frame_height * BYTES_PER_PIXEL);
        pData->frameReady = YES ;		
		
	}
    pData->moviePlaying = NO;
    pData->movieFinished = YES;
die:	
    
	pthread_exit(NULL);
    
}

@implementation MoviePlayerController
@synthesize useES1;
- (void) dealloc{
    [renderer release];
    [self closeMovie];
    [super dealloc];
}
- (void) bufferDone{
    stateInst.frameReady = NO;
}
- (BOOL) resizeFromLayer:(CAEAGLLayer *)layer{
    return [renderer resizeFromLayer:layer];
}

- (id) init {
    self = [super init];
    
    useES1 = NO;
    renderer = [[ES2Renderer alloc] init];
    
    if(!renderer){
        useES1 = YES;
        renderer = [[ES1Renderer alloc] init];
    }
    
    [renderer setMoviePlayerDelegate:self];
    return self;
}
- (void) render {
    if(!stateInst.frameReady) return;
    
    [renderer render: stateInst.pOutBuffer];
    
}
- (int) loadVideoFile:(const char *)file{
    
	setupPlayer();
    
    stateInst.movieOpen = NO;
    stateInst.movieFinished = NO;
    
	stateInst.pVideoInst = openMovie(file);
    
	if(!stateInst.pVideoInst){
		NSLog(@"Unable to open video.");
    	return NO;
	}
	UIApplication* myApp = [UIApplication sharedApplication];
    myApp.idleTimerDisabled = YES;
    
	mWidth  = stateInst.pVideoInst->video.frame_width;
	mHeight = stateInst.pVideoInst->video.frame_height;
	
    texW = mWidth;
    texH = mHeight;
    next_powerof2(texW); 
    next_powerof2(texH);
    
    if(stateInst.pOutBuffer){
        free (stateInst.pOutBuffer);
        stateInst.pOutBuffer = 0;
    }
    stateInst.pOutBuffer = (uint8_t*) calloc(mWidth*mHeight*2,1);
        
    [renderer prepareTextureW: texW textureHeight: texH frameWidth: mWidth frameHeight: mHeight];
    
    
    if(stateInst.pVideoInst->audio.has_audio) {
		stateInst.pAqInst = [[AQHandler alloc] initWithAVDetails:stateInst.pVideoInst];
	}
    stateInst.movieOpen = YES;
	return stateInst.movieOpen;
}
- (int) play {
    struct sched_param param;
    
    if (stateInst.moviePlaying || !stateInst.movieOpen) return -1 ;
    
    usleep(10000);
    stateInst.moviePlaying  = YES;
    
    if(stateInst.pVideoInst->audio.has_audio)     [stateInst.pAqInst startPlayback];
    
    stateInst.killThread = 0;
    param.sched_priority = sched_get_priority_max(SCHED_RR)-10;
    
    pthread_create(&stateInst.thread, NULL, runMovie, &stateInst);
    pthread_setschedparam(stateInst.thread, SCHED_RR, &param);
    
    return 0;
}
- (int) seekToTime: (int) timeInSeconds{
    BOOL playing = stateInst.moviePlaying;
    if(!stateInst.movieOpen) return 0 ;
    [self pause];
    if(stateInst.pAqInst) {
        [stateInst.pAqInst release];
        stateInst.pAqInst = [[AQHandler alloc] initWithAVDetails:stateInst.pVideoInst];
    }
    seekToTime(stateInst.pVideoInst,timeInSeconds);
    usleep(5000);
    if(playing)
        [self play];
    return 1;
}
- (int) pause{
    if(!stateInst.movieOpen) return 0 ;
    if(stateInst.pVideoInst->audio.has_audio) [stateInst.pAqInst pausePlayback];
    stateInst.killThread = 1;
    usleep(1000);
    
    stateInst.moviePlaying = NO;
    
    return stateInst.moviePlaying;
}

- (int) stop{
    if(!stateInst.movieOpen) return 0 ;
    [self seekToTime:0];
    [self pause];
    
    return stateInst.moviePlaying;
}

- (void) closeMovie{
    if(stateInst.moviePlaying) [self stop];
    if(stateInst.movieOpen) closeMovie(stateInst.pVideoInst);
    
    if(stateInst.pVideoInst->audio.has_audio) [stateInst.pAqInst release];
    
    
    if(stateInst.pOutBuffer){
        free (stateInst.pOutBuffer);
        stateInst.pOutBuffer = 0;
    }
    
    stateInst.frameReady = NO;
    
    pthread_detach(stateInst.thread);
    
    stateInst.movieOpen = NO;
}
- (BOOL) movieIsLoaded {
    return stateInst.movieOpen;
}
- (BOOL) movieIsPlaying {
    return stateInst.moviePlaying;
}
- (BOOL) movieIsFinished{
    return stateInst.movieFinished;
}
- (int64_t) getMovieTimeInSeconds {
    return stateInst.currentPTS / stateInst.pVideoInst->video.fps_den;
}
- (int64_t) getMovieDurationInSeconds {
    return stateInst.pVideoInst->video.duration / (stateInst.pVideoInst->video.fps_num / stateInst.pVideoInst->video.fps_den) ;
}
@end
