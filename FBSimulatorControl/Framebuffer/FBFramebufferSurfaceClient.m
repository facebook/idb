/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferSurfaceClient.h"

#import <IOSurface/IOSurfaceAPI.h>

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderable-Protocol.h>
#import <SimulatorKit/SimDisplayRenderable-Protocol.h>

#import <CoreSimulator/SimDeviceIOClient.h>

@interface FBFramebufferSurfaceClient_FramebufferService : FBFramebufferSurfaceClient

@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;
@property (nonatomic, strong, readwrite) SimDeviceFramebufferService *framebufferService;
@property (nonatomic, strong, readwrite) void (^callback)(IOSurfaceRef);

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService clientQueue:(dispatch_queue_t)clientQueue;

@end

@interface FBFramebufferSurfaceClient_IOClient : FBFramebufferSurfaceClient

@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;
@property (nonatomic, strong, readwrite) SimDeviceIOClient *ioClient;

- (instancetype)initWithIOClient:(SimDeviceIOClient *)ioClient clientQueue:(dispatch_queue_t)clientQueue;

@end

@implementation FBFramebufferSurfaceClient

+ (instancetype)clientForFramebufferService:(SimDeviceFramebufferService *)framebufferService clientQueue:(dispatch_queue_t)clientQueue
{
  return [[FBFramebufferSurfaceClient_FramebufferService alloc] initWithFramebufferService:framebufferService clientQueue:clientQueue];
}

+ (instancetype)clientForIOClient:(SimDeviceIOClient *)ioClient clientQueue:(dispatch_queue_t)clientQueue
{
  return [[FBFramebufferSurfaceClient_IOClient alloc] initWithIOClient:ioClient clientQueue:clientQueue];
}

- (void)obtainSurface:(void (^)(IOSurfaceRef))callback
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)detach
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

+ (void)detachFromFramebufferService:(SimDeviceFramebufferService *)framebufferService
{
  [framebufferService unregisterClient:self];

  // Only call invalidate if the selector exists.
  if ([framebufferService respondsToSelector:@selector(invalidate)]) {
    // The call to this method has been dropped in Xcode 8.1, but exists in Xcode 8.0
    // Don't call it on Xcode 8.1
    if ([FBControlCoreGlobalConfiguration.xcodeVersionNumber isLessThan:[NSDecimalNumber decimalNumberWithString:@"8.1"]]) {
      [framebufferService invalidate];
    }
  }
}

@end

@implementation FBFramebufferSurfaceClient_FramebufferService

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService clientQueue:(dispatch_queue_t)clientQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _framebufferService = framebufferService;
  _clientQueue = clientQueue;

  return self;
}

- (void)obtainSurface:(void (^)(IOSurfaceRef))callback
{
  NSParameterAssert(callback != nil);
  NSParameterAssert(self.callback == nil);
  self.callback = callback;
  [self.framebufferService registerClient:self onQueue:self.clientQueue];
  [self.framebufferService resume];
}

- (void)detach
{
  [FBFramebufferSurfaceClient detachFromFramebufferService:self.framebufferService];
  // Release the Service by removing the reference.
  _framebufferService = nil;
}

- (void)setIOSurface:(IOSurfaceRef)surface
{
  NSParameterAssert(self.callback);
  self.callback(surface);
}

@end

@implementation FBFramebufferSurfaceClient_IOClient

- (instancetype)initWithIOClient:(SimDeviceIOClient *)ioClient clientQueue:(dispatch_queue_t)clientQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _ioClient = ioClient;
  _clientQueue = clientQueue;

  return self;
}

- (void)obtainSurface:(void (^)(IOSurfaceRef))callback
{
  NSParameterAssert(callback != nil);
  IOSurfaceRef surface = [self surfaceFromIOClient];
  dispatch_async(self.clientQueue, ^{
    callback(surface);
  });
}

- (void)detach
{
}

#pragma mark Private

- (IOSurfaceRef)surfaceFromIOClient
{
  for (id<SimDeviceIOPortInterface> port in self.ioClient.ioPorts) {
    if (![port conformsToProtocol:@protocol(SimDeviceIOPortInterface)]) {
      continue;
    }
    id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> renderable = (id) [port descriptor];
    if (![renderable conformsToProtocol:@protocol(SimDisplayRenderable)]) {
      continue;
    }
    if (![renderable conformsToProtocol:@protocol(SimDisplayIOSurfaceRenderable)]) {
      continue;
    }
    IOSurfaceRef surface = IOSurfaceLookupFromXPCObject(renderable.ioSurface);
    if (!surface) {
      continue;
    }
    return surface;
  }
  return nil;
}

@end
