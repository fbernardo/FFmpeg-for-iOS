/*
 * ES1Renderer.h/.m - Handle rendering in an OpenGLES1.1 context
 * Supports anaglyph and line-interlaced(polarized) mode.
 * jamesghurley<at>gmail.com
 */

#import "ES1Renderer.h"
#import "AQHandler.h"
#import <stdio.h>
#import <unistd.h>
#import "video_inst.h"
#import "mach_util.h"
#include <pthread.h>
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include <libkern/OSAtomic.h>

 
#define IMG_FMT_BYTES 2	// Number of bytes per pixel.


// Assist conditional prediction
#ifdef __GNUC__
#define likely(x)       __builtin_expect(!!(x),1)
#define unlikely(x)     __builtin_expect(!!(x),0)
#else
#define likely(x) (x)
#define unlikely(x) (x)
#endif


@interface ES1Renderer (Private)
- (void) renderAnaglyph;
- (void) renderInterlaced;
- (void) generateVertices;
@end


// ---------------------------------------------
@implementation ES1Renderer


// Create an ES 1.1 context

- (id) init
{
	
    
	if (self = [super init])
	{
		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
      
    

        if (!context || ![EAGLContext setCurrentContext:context])
		{
            [self release];
            return nil;
        }
        NSLog(@"ES1Renderer");
		// Create default framebuffer object. The backing will be allocated for the current layer in -resizeFromLayer
		glGenFramebuffersOES(1, &defaultFramebuffer);
		glGenRenderbuffersOES(1, &colorRenderbuffer);
		glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
		glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
		glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, colorRenderbuffer);

	}
	
	return self;
}
- (void) setMoviePlayerDelegate: (id<MoviePlayerStateNotify>) del{
    
    moviePlayerDelegate = del;
    
}
- (void) prepareTextureW: (uint) texW textureHeight: (uint) texH frameWidth:(uint) frameW frameHeight: (uint) frameH{
    printf("prepareTextureW\n");
    mTexW = texW;
    mTexH = texH;
    mFrameW = frameW;
    mFrameH = frameH;
    glEnable(GL_TEXTURE_2D);
    glGenTextures(1, &frameTexture);
    glBindTexture(GL_TEXTURE_2D, frameTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT );
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT );
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, texW, texH, 0, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, NULL);
    [self generateVertices];
}
#pragma mark render
- (void) render: (uint8_t*) buffer
{
    [EAGLContext setCurrentContext:context];
    glColor4f(1.f, 1.f, 1.f, 1.f);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, mFrameW, mFrameH, GL_RGB,GL_UNSIGNED_SHORT_5_6_5, buffer);
       
    //[self performSelector:_renderer];
      
    glTexCoordPointer(2, GL_FLOAT, 0, agCoord);
    glDrawArrays(GL_TRIANGLES, 0, 6);

    [moviePlayerDelegate bufferDone];
    
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER_OES];
}
- (void) generateVertices {

    int sizeX = backingHeight;
    int sizeY = backingWidth;
 
 
    if(agVert){
        free(agVert); agVert = 0L;
    }
    if(agCoord){
        free(agCoord); agCoord = 0L;
    }
    
    agVert = calloc(1, sizeof(float)*6);
    agCoord = calloc(1,sizeof(float)*6);
    
    
    float maxS = (float)mFrameW/(float)mTexW;
    float maxT = (float)mFrameH/(float)mTexH;
    
    agVert[0] = (float)sizeX;
    agVert[1] = (float)sizeY;
    agVert[2] = 0.0;
    agVert[3] = (float)sizeY;
    agVert[4] = (float)sizeX;
    agVert[5] = 0.0;
    
    agCoord[0] = maxS;     agCoord[1] = 0.f;
    agCoord[2] = 0.f;      agCoord[3] = 0.f;
    agCoord[4] = maxS;     agCoord[5] = maxT;
    
    

   
}
- (BOOL) resizeFromLayer:(CAEAGLLayer *)layer
{	
    printf("resizeFromLayer\n");
	// Allocate color buffer backing based on the current layer size
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:layer];
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
	
    if (glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES)
	{
		NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
        return NO;
    }
    

    
    
    glViewport(0, 0, backingWidth, backingHeight);
    glOrthof(0.0f, backingWidth, 0.0f, backingHeight, -1.0f, 1.0f);
    

    glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_RGB, GL_MODULATE);
    
    // ---------------------------------------------------------------
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
    glViewport(0, 0, backingWidth, backingHeight);
    glMatrixMode(GL_TEXTURE);
    glLoadIdentity();
    
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glViewport(0, 0, backingWidth, backingHeight);
    glOrthof(0.0f, backingWidth, 0.0f, backingHeight, -1.0f, 1.0f);
    
    glRotatef(-90.f, 0.f,0.f, 1.f);
    glTranslatef(-backingHeight, 0.0, 0.0);
    
    return YES;
}

- (void) dealloc
{
	// Tear down GL
	if (defaultFramebuffer)
	{
		glDeleteFramebuffersOES(1, &defaultFramebuffer);
		defaultFramebuffer = 0;
	}
    
	if (colorRenderbuffer)
	{
		glDeleteRenderbuffersOES(1, &colorRenderbuffer);
		colorRenderbuffer = 0;
	}
	
	// Tear down context
	if ([EAGLContext currentContext] == context)
        [EAGLContext setCurrentContext:nil];
  
    if(agVert)    free(agVert);
    if(agCoord)   free(agCoord);
	[context release];
	context = nil;
	
     
	[super dealloc];
}

@end
