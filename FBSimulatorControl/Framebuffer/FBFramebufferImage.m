/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferImage.h"

#import "FBDiagnostic.h"
#import "FBSimulatorEventSink.h"

@interface FBFramebufferImage ()

@property (atomic, assign, readwrite) CGImageRef image;

@property (nonatomic, strong, readonly) FBDiagnostic *diagnostic;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

@end

@implementation FBFramebufferImage

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink
{
  return [[self alloc] initWithDiagnostic:diagnostic eventSink:eventSink];
}

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = [diagnostic copy];
  _eventSink = eventSink;

  return self;
}

- (void)dealloc
{
  CGImageRelease(_image);
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

- (void)framebufferDidUpdate:(FBSimulatorFramebuffer *)framebuffer withImage:(CGImageRef)image count:(NSUInteger)count size:(CGSize)size
{
  CGImageRef oldImage = self.image;
  self.image = CGImageRetain(image);
  CGImageRelease(oldImage);
}

- (void)framebufferDidBecomeInvalid:(FBSimulatorFramebuffer *)framebuffer error:(NSError *)error
{
  FBDiagnostic *diagnostic = [FBFramebufferImage appendImage:self.image toDiagnostic:self.diagnostic];
  id<FBSimulatorEventSink> eventSink = self.eventSink;

  dispatch_async(dispatch_get_main_queue(), ^{
    [eventSink diagnosticAvailable:diagnostic];
  });
}

@end
