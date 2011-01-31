/*
 * ES2Renderer.h/.m - Handle rendering in an OpenGLES2.0 context
 * Supports anaglyph and line-interlaced(polarized) mode.
 * jamesghurley<at>gmail.com
 */

#import "ES2Renderer.h"
#import "mach_util.h"
#import <unistd.h>


// Texture upload is fairly slow, especially on pre-iOS 4.0 devices.  
// Using RGB565 reduces bandwidth requirements.
#define BYTES_PER_PIXEL 2


@interface ES2Renderer (Private)
- (void) setupShader ;

@end
@implementation ES2Renderer


- (id)init
{
    if ((self = [super init]))
    {
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

        if (!context || ![EAGLContext setCurrentContext:context])
        {
            [self release];
            return nil;
        }
        shader = [[GLShader alloc] initWithFileName:@"render" attributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                                                 [NSNumber numberWithInt:0], @"position",
                                                                                                 [NSNumber numberWithInt:1], @"texCoords", nil]
                                             uniforms:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:0], @"sampler0",
                                                                                                 [NSNumber numberWithInt:0], @"viewProjectionMatrix",nil]];

        if(!shader) {
            [self release];
            return nil;
        }
        NSLog(@"ES2Renderer");
        
        // Create default framebuffer object. The backing will be allocated for the current layer in -resizeFromLayer
        glGenFramebuffers(1, &defaultFramebuffer);
        glGenRenderbuffers(1, &colorRenderbuffer);
        glGenRenderbuffers(1, &depthBuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depthBuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthBuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
        
        
    }

    return self;
}
- (void) setMoviePlayerDelegate: (id<MoviePlayerStateNotify>) del{
    moviePlayerDelegate = del;
    
}
- (void) prepareTextureW: (GLuint) texW textureHeight: (GLuint) texH frameWidth: (GLuint) frameW frameHeight: (GLuint) frameH {
    
    float aspect = (float)frameW/(float)frameH;
    float minX=-1.f, minY=-1.f, maxX=1.f, maxY=1.f;
    float scale ;
    if(aspect>=(float)backingHeight/(float)backingWidth){
        // Aspect ratio will retain width.
        scale = (float)backingHeight / (float) frameW;
        maxY = ((float)frameH * scale) / (float) backingWidth;
        minY = -maxY;
    } else {
        // Retain height.
        scale = (float) backingWidth / (float) frameW;
        maxX = ((float) frameW * scale) / (float) backingHeight;
        minX = -maxX;
    }
    if(frameTexture) glDeleteTextures(1, &frameTexture);
    glEnable(GL_TEXTURE_2D);
    glGenTextures(1, &frameTexture);
    glBindTexture(GL_TEXTURE_2D, frameTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT );
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT );
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, texW, texH, 0, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, NULL);
    
    
    verts[0] = minX;           verts[1] = minY;
    verts[2] = maxX;           verts[3] = minY;
    verts[4] = minX;           verts[5] = maxY;
    verts[6] = maxX;           verts[7] = maxY;
    
    float s = (float) frameW / (float) texW;
    float t = (float) frameH / (float) texH;
    
    texCoords[0] = 0.f;        texCoords[1] = 0.f;
    texCoords[2] = s;          texCoords[3] = 0.f;
    texCoords[4] = 0.f;        texCoords[5] = t;
    texCoords[6] = s;          texCoords[7] = t;
    
    mFrameH = frameH;
    mFrameW = frameW;
    mTexH = texH;
    mTexW = texW;
    maxS = s;
    maxT = t;
    
    matSetPerspective(&proj, -1, 1, 1,-1, -1, 1);
    // Just supporting one rotation direction, landscape left.  Rotate Z by 90 degrees.
    matSetRotZ(&rot,M_PI_2);
	
	matMul(&mvp, &rot, &proj);
    [self setupShader];
    
}
- (void) setupShader {
        
    glUseProgram(shader.program);
    glUniformMatrix4fv([shader getUniform:@"viewProjectionMatrix"], 1, FALSE, (GLfloat*)&mvp.m[0]);
    glUniform1i([shader getUniform:@"sampler0"], 0);
    
    glVertexAttribPointer([shader getAttribute:@"position"], 2, GL_FLOAT, 0, 0, verts);
    glEnableVertexAttribArray([shader getAttribute:@"position"]);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 2);
    glEnable(GL_TEXTURE_2D);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, frameTexture);
    glVertexAttribPointer([shader getAttribute:@"texCoords"], 2, GL_FLOAT, 0, 0, texCoords);
    glEnableVertexAttribArray([shader getAttribute:@"texCoords"]);

    
}

- (void) render: (uint8_t*) buffer
{
    [EAGLContext setCurrentContext:context];

    glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
    glViewport(0, 0, backingWidth, backingHeight);
 
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // OpenGL loads textures lazily so accessing the buffer is deferred until draw; notify
    // the movie player that we're done with the texture after glDrawArrays.
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, mFrameW, mFrameH, GL_RGB,GL_UNSIGNED_SHORT_5_6_5, buffer);
        
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    [moviePlayerDelegate bufferDone];
    
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER];
}


- (BOOL)resizeFromLayer:(CAEAGLLayer *)layer
{
    // Allocate color buffer backing based on the current layer size
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        return NO;
    }

    return YES;
}

- (void)dealloc
{
    // Tear down GL
    if (defaultFramebuffer)
    {
        glDeleteFramebuffers(1, &defaultFramebuffer);
        defaultFramebuffer = 0;
    }

    if (colorRenderbuffer)
    {
        glDeleteRenderbuffers(1, &colorRenderbuffer);
        colorRenderbuffer = 0;
    }


    if(shader) {
        [shader release];
    }
    // Tear down context
    if ([EAGLContext currentContext] == context)
        [EAGLContext setCurrentContext:nil];

    [context release];
    context = nil;

    [super dealloc];
}

@end
