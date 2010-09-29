//
//  Video_Player_DemoAppDelegate.h
//  Video_Player Demo
//
//  Created by James Hurley on 10-09-02.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "EAGLMessageProtocol.h"
@class EAGLView;

@interface Video_Player_DemoAppDelegate : NSObject <UIApplicationDelegate, EAGLMessageProtocol> {
    UIWindow *window;
    EAGLView *glView;
    UILabel *label;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet EAGLView *glView;
@property (nonatomic, retain) IBOutlet UILabel *label;
@end

