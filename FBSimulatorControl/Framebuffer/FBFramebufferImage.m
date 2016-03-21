/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferImage.h"

#import <FBControlCore/FBControlCore.h>

#import "FBFramebufferFrame.h"
#import "FBSimulatorEventSink.h"

@interface FBFramebufferImage ()

@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readwrite) FBFramebufferFrame *lastFrame;

@property (nonatomic, strong, readonly) FBDiagnostic *diagnostic;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

@end

@implementation FBFramebufferImage

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBSimulatorControl.framebuffer.image", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithDiagnostic:diagnostic eventSink:eventSink writeQueue:queue];
}

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink writeQueue:(dispatch_queue_t)writeQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = [diagnostic copy];
  _eventSink = eventSink;
  _writeQueue = writeQueue;

  return self;
}

#pragma mark Public

+ (FBDiagnostic *)appendImage:(CGImageRef)image toDiagnostic:(FBDiagnostic *)diagnostic
{
  FBDiagnosticBuilder *builder = [FBDiagnosticBuilder builderWithDiagnostic:diagnostic];
  NSString *filePath = [builder createPath];
  NSURL *url = [NSURL fileURLWithPath:filePath];
  CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
    (__bridge CFURLRef) url,
    kUTTypePNG,
    1,
    NULL
  );
  if (!url) {
    return diagnostic;
  }
  CGImageDestinationAddImage(destination, image, NULL);
  if (!CGImageDestinationFinalize(destination)) {
    return diagnostic;
  }
  CFRelease(destination);

  return [[builder updatePath:filePath] build];
}

#pragma mark FBFramebufferCounterDelegate Implementation

- (void)framebuffer:(FBFramebuffer *)framebuffer didUpdate:(FBFramebufferFrame *)frame
{
  dispatch_async(self.writeQueue, ^{
    self.lastFrame = frame;
  });
}

- (void)framebuffer:(FBFramebuffer *)framebuffer didBecomeInvalidWithError:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  dispatch_group_async(teardownGroup, self.writeQueue, ^{
    FBDiagnostic *diagnostic = [FBFramebufferImage appendImage:self.lastFrame.image toDiagnostic:self.diagnostic];
    id<FBSimulatorEventSink> eventSink = self.eventSink;
    dispatch_async(dispatch_get_main_queue(), ^{
      [eventSink diagnosticAvailable:diagnostic];
    });
  });
}

@end
