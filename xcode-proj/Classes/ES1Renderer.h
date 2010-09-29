/*
 * ES1Renderer.h/.m - Handle rendering in an OpenGLES1.1 context
 * Supports anaglyph and line-interlaced(polarized) mode.
 * jamesghurley<at>gmail.com
 */
#import "ESRenderer.h"

#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>


@interface ES1Renderer : NSObject <ESRenderer>
{
@private
    EAGLContext *context;
	
	// The pixel dimensions of the CAEAGLLayer
    GLint backingWidth;
    GLint backingHeight;
	
	// The OpenGL names for the framebuffer and renderbuffer used to render to this view
    GLuint defaultFramebuffer, colorRenderbuffer;
      
    GLuint frameTexture;
    GLfloat *agVert, *agCoord; // Vertices and coordinates for interlaced and anaglyph modes.
    GLuint agCount;
    
    GLuint mTexW, mTexH, mFrameW, mFrameH;

    id<MoviePlayerStateNotify> moviePlayerDelegate;
}

@end
