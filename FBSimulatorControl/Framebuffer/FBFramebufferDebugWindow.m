/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferDebugWindow.h"

#import <Cocoa/Cocoa.h>

#import "FBFramebufferFrame.h"

@interface FBFramebufferDebugWindow () <NSApplicationDelegate>

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, strong, readwrite) NSWindow *window;

@end

@implementation FBFramebufferDebugWindow

@synthesize window = _window;

#pragma mark Initializers

+ (instancetype)withName:(NSString *)name;
{
  return [[self alloc] initWithName:name];
}

- (instancetype)initWithName:(NSString *)name
{
  NSParameterAssert(name);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;

  return self;
}

- (void)dealloc
{
  [self teardownWindow];
}

#pragma mark FBFramebufferDelegate Implementation

- (void)framebuffer:(FBFramebuffer *)framebuffer didUpdate:(FBFramebufferFrame *)frame
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (frame.count == 0) {
      self.window = [self createWindowWithSize:frame.size];
    }
    [self updateWindowWithImage:frame.image];
  });
}

- (void)framebuffer:(FBFramebuffer *)framebuffer didBecomeInvalidWithError:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  [self teardownWindow];
}

#pragma mark Private

- (void)teardownWindow
{
  NSWindow *window = self.window;
  self.window = nil;
  dispatch_async(dispatch_get_main_queue(), ^{
    [window close];
  });
}

- (void)updateWindowWithImage:(CGImageRef)image
{
  self.window.contentView.layer.contents = (__bridge id) image;
}

- (NSWindow *)createWindowWithSize:(CGSize)size
{
  [NSApplication sharedApplication];
  [NSApp setDelegate:self];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  NSRect initialPosition = [[NSScreen mainScreen] frame];
  initialPosition = (NSRect) { .size = size, .origin = CGPointZero };
  NSWindow *window = [[NSWindow alloc] initWithContentRect:initialPosition styleMask:NSTitledWindowMask | NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO];
  window.backgroundColor = NSColor.whiteColor;
  window.contentView.wantsLayer = YES;
  window.title = self.name;
  [window makeKeyAndOrderFront:NSApp];
  [window display];

  [NSApp activateIgnoringOtherApps:YES];

  return window;
}

#pragma mark NSApplicationDelegate

- (void)applicationWillBecomeActive:(NSNotification *)aNotification
{
  [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
  [NSApp activateIgnoringOtherApps:YES];
  return YES;
}

@end
