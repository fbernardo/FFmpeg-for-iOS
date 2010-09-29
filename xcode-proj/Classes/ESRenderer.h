//
//  ESRenderer.h
//  SVIPlayer
//
//  Created by James Hurley on 10-05-14.
//  Copyright __MyCompanyName__ 2010. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>

@protocol MoviePlayerStateNotify
- (void) bufferDone;
@end

@protocol ESRenderer <NSObject>

- (void) setMoviePlayerDelegate: (id<MoviePlayerStateNotify>) del;
- (void) render: (uint8_t*) buffer;
- (BOOL) resizeFromLayer:(CAEAGLLayer *)layer;
- (void) prepareTextureW: (uint) texW textureHeight: (uint) texH frameWidth:(uint) frameW frameHeight: (uint) frameH;

@end
