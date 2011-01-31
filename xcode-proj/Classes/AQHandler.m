/*  AQHandler.h/.c - AudioQueue handler
 *  jamesghurley<at>gmail.com
 * 
 */

#import "AQHandler.h"
#import "mach_util.h"

#define AUDIO_FORMAT_AAC 0x15002 

static AQHandler* t;
//static unsigned int				bufLength;
static 	UInt32 numPacketsToRead;
static 	video_data_t* _av;
static 	UInt64 startTime;
static  int aqStartDts=-1  ;

#pragma mark C Prototypes


static void DeriveBufferSize (AudioStreamBasicDescription ASBDesc, UInt32 maxPacketSize,Float64 seconds, UInt32 *outBufferSize, UInt32 *outNumPacketsToRead);
static void fillAudioBuffer(AudioQueueRef queue, AudioQueueBufferRef buffer);
static char *FormatError(char *str, OSStatus error);



#pragma mark AudioQueue callback
/* ----------------------------------------------------------------------------------
 * Callback called by AudioQueue to refill buffers.
 *
 * ---------------------------------------------------------------------------------- */

static void aqCallback(void *info, AudioQueueRef queue, AudioQueueBufferRef buffer) {
	fillAudioBuffer(queue, buffer);
}



#pragma mark AQHandler Implementation
@implementation AQHandler
- (UInt64) GetStartTime {
    return startTime;
}
- (BOOL) isPlaying{
	return playState.playing;
}
/* ---------------------------------------------------------------------------------------------- */
- (id) initWithAVDetails: (video_data_t*) av {
	self = [super init];
	t = self;
	_av = av;
    aqStartDts=-1;
	return self;
}

/* ---------------------------------------------------------------------------------------------- */
- (void) startPlayback{
    OSStatus err = 0;
    if(playState.playing) return;
    PMSG2("AQHandler: startPlayback\n");
	if(!playState.queue) {
        
        
        UInt32 bufferSize;
        
        playState.format.mSampleRate = _av->audio.sample_rate;
        playState.format.mFormatFlags = (_av->audio.format_id == AUDIO_FORMAT_AAC ? kMPEG4Object_AAC_LC : 0);
        playState.format.mFormatID = (_av->audio.format_id == AUDIO_FORMAT_AAC ? kAudioFormatMPEG4AAC : kAudioFormatMPEGLayer3);
        playState.format.mBytesPerPacket = _av->audio.bytes_per_packet;
        playState.format.mFramesPerPacket = _av->audio.frame_size;
        playState.format.mChannelsPerFrame = _av->audio.channels_per_frame;
        playState.format.mBitsPerChannel = 16;
        playState.format.mBytesPerFrame = _av->audio.bytes_per_frame;
        
        pauseStart = 0;
    
        DeriveBufferSize(playState.format,_av->audio.bytes_per_packet,BUFFER_DURATION,&bufferSize,&numPacketsToRead);
   
        
        err= AudioQueueNewOutput(&playState.format, aqCallback, &playState, NULL, NULL, 0, &playState.queue);
        
        if(err != 0){
            PMSG2("AQHandler.m startPlayback: Error creating new AudioQueue: %d \n", (int)err);
        }
        
        
        for(int i = 0 ; i < NUM_BUFFERS ; i ++){
            err = AudioQueueAllocateBufferWithPacketDescriptions(playState.queue, bufferSize, numPacketsToRead , &playState.buffers[i]);
            if(err != 0)
                PMSG2("AQHandler.m startPlayback: Error allocating buffer %d", i);
            fillAudioBuffer(playState.queue, playState.buffers[i]);
            
        }
        
    }
    
	startTime = mu_currentTimeInMicros();

    
    if(err=AudioQueueStart(playState.queue, NULL)){
#ifdef DEBUG
        char sErr[4];
		PMSG2(@"AQHandler.m startPlayback: Could not start queue %d %s.", err, FormatError(sErr,err));
#endif
        playState.playing = NO;
	} else{
        playState.playing = YES;
        
    }	
	
	
}

- (void) pausePlayback {
    AudioQueuePause(playState.queue);
    playState.playing = NO;
 
}
- (void) stopPlayback{
	AudioQueueStop(playState.queue, YES);
	playState.playing = NO;
    aqStartDts=-1;
}
- (void) disposeQueue{
    if(playState.queue)
        AudioQueueDispose(playState.queue, YES);
    
    playState.queue = 0;
    playState.playing = NO;
}
- (void) clearBuffers{
    for(int i = 0 ; i < NUM_BUFFERS; i ++ )
    AudioQueueFreeBuffer(playState.queue, playState.buffers[i]);

}
- (void) dealloc{
    [self disposeQueue];
    [super dealloc];
}
- (Float64) GetCurrentTime {
	AudioTimeStamp bufferTime ;
	AudioQueueGetCurrentTime(playState.queue, NULL, &bufferTime, NULL);
	return bufferTime.mSampleTime;
}
@end

#pragma mark C Definitions
/* ---------------------------------------------------------------------------------------------- */
static void DeriveBufferSize (
					   AudioStreamBasicDescription ASBDesc,                            
					   UInt32                      maxPacketSize,                       
					   Float64                     seconds,                             
					   UInt32                      *outBufferSize,                      
					   UInt32                      *outNumPacketsToRead                 
					   ) {
    static const int maxBufferSize = 0x50000;                        
    static const int minBufferSize = 0x4000;                         
	
    if (ASBDesc.mFramesPerPacket != 0) {                             
        Float64 numPacketsForTime =
		ASBDesc.mSampleRate / ASBDesc.mFramesPerPacket * seconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    } else {                                                         
        *outBufferSize =
		maxBufferSize > maxPacketSize ?
		maxBufferSize : maxPacketSize;
    }
	
    if (                                                             
        *outBufferSize > maxBufferSize &&
        *outBufferSize > maxPacketSize
		)
        *outBufferSize = maxBufferSize;
    else {                                                           
        if (*outBufferSize < minBufferSize)
            *outBufferSize = minBufferSize;
    }
	
    *outNumPacketsToRead = *outBufferSize / maxPacketSize;           
}
/* ---------------------------------------------------------------------------------------------- */

static void fillAudioBuffer(AudioQueueRef queue, AudioQueueBufferRef buffer){
	
	int lengthCopied = INT32_MAX;
	int dts= 0;
	int isDone = 0;

	buffer->mAudioDataByteSize = 0;
	buffer->mPacketDescriptionCount = 0;
	
	OSStatus err = 0;
	AudioTimeStamp bufferStartTime;

	AudioQueueGetCurrentTime(queue, NULL, &bufferStartTime, NULL);
	

	
	while(buffer->mPacketDescriptionCount < numPacketsToRead && lengthCopied > 0){
		if (buffer->mAudioDataByteSize) {
			break;
		}
		
		lengthCopied = getNextAudio(_av,buffer->mAudioDataBytesCapacity-buffer->mAudioDataByteSize, (uint8_t*)buffer->mAudioData+buffer->mAudioDataByteSize,&dts,&isDone);
		if(!lengthCopied || isDone) break;
      
        if(aqStartDts < 0) aqStartDts = dts;
		if(buffer->mPacketDescriptionCount ==0){
			bufferStartTime.mFlags = kAudioTimeStampSampleTimeValid;
			bufferStartTime.mSampleTime = (Float64)(dts-aqStartDts) * _av->audio.frame_size;
			
            if (bufferStartTime.mSampleTime <0 ) bufferStartTime.mSampleTime = 0;
			PMSG1("AQHandler.m fillAudioBuffer: DTS for %x: %lf time base: %lf StartDTS: %d\n", (unsigned int)buffer, bufferStartTime.mSampleTime, _av->audio.time_base, aqStartDts);
			
		}
		buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
		buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = lengthCopied;
		buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = _av->audio.frame_size;
		
		buffer->mPacketDescriptionCount++;
		buffer->mAudioDataByteSize += lengthCopied;
		
	}
	
#ifdef DEBUG
	int audioBufferCount, audioBufferTotal,  videoBufferCount, videoBufferTotal;
	bufferCheck(_av,&videoBufferCount, &videoBufferTotal, &audioBufferCount, &audioBufferTotal);
	
	PMSG2("AQHandler.m fillAudioBuffer: Video Buffer: %d/%d Audio Buffer: %d/%d\n", videoBufferCount, videoBufferTotal, audioBufferCount, audioBufferTotal);
	
	PMSG2("AQHandler.m fillAudioBuffer: Bytes copied for buffer 0x%x: %d\n",(unsigned int)buffer, (int)buffer->mAudioDataByteSize );
#endif	
	if(buffer->mAudioDataByteSize){
		
		if(err=AudioQueueEnqueueBufferWithParameters(queue, buffer, 0, NULL, 0, 0, 0, NULL, &bufferStartTime, NULL))
		{
#ifdef DEBUG
			char sErr[10];

			PMSG2(@"AQHandler.m fillAudioBuffer: Could not enqueue buffer 0x%x: %d %s.", buffer, err, FormatError(sErr, err));
#endif
		}
	}

}
/* ---------------------------------------------------------------------------------------------- */
static char *FormatError(char *str, OSStatus error)
{
    // see if it appears to be a 4-char-code
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else
        // no, format it as an integer
        sprintf(str, "%d", (int)error);
    return str;
}