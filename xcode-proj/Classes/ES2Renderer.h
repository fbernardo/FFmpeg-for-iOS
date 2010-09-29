/*
 * ES2Renderer.h/.m - Handle rendering in an OpenGLES2.0 context
 * Supports anaglyph and line-interlaced(polarized) mode.
 * jamesghurley<at>gmail.com
 */

#import "ESRenderer.h"
#import "Matrix4x4.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import "GLShader.h"

@interface ES2Renderer : NSObject <ESRenderer>
{
@private
    EAGLContext *context;

    GLint backingWidth;
    GLint backingHeight;

    GLuint defaultFramebuffer, colorRenderbuffer;
    GLuint depthBuffer, frameTexture;
    
    uint mFrameW, mFrameH, mTexW, mTexH;
    float maxS, maxT;
    
    GLuint sampler0 ; 
    
    GLfloat verts[8];
    GLfloat texCoords[8];
    
    Matrix4x4 proj, rot, mvp;
    GLShader *shader;

    GLuint program;
    id<MoviePlayerStateNotify> moviePlayerDelegate;
}

@end

