/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFramebuffer.h"

#import <CoreSimulator/SimDeviceIOProtocol-Protocol.h>

#import <xpc/xpc.h>

#import <IOSurface/IOSurface.h>

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>

#import <SimulatorKit/SimDeviceIOPortConsumer-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortDescriptorState-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayDescriptorState-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderable-Protocol.h>
#import <SimulatorKit/SimDisplayRenderable-Protocol.h>

#import <IOSurface/IOSurfaceObjC.h>

#import "FBSimulator+Private.h"
#import "FBSimulatorError.h"

@interface FBFramebuffer ()

@property (nonatomic, strong, readonly) NSMapTable<id<FBFramebufferConsumer>, NSUUID *> *consumers;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@interface FBFramebuffer_Legacy : FBFramebuffer

@property (nonatomic, strong, readonly) id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> surface;

- (instancetype)initWithSurface:(id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable>)surface logger:(id<FBControlCoreLogger>)logger;

@end

@implementation FBFramebuffer

#pragma mark Initializers

+ (instancetype)mainScreenSurfaceForSimulator:(FBSimulator *)simulator logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;
{
  id<SimDeviceIOProtocol> ioClient = simulator.device.io;
  for (id<SimDeviceIOPortInterface> port in ioClient.ioPorts) {
    if (![port conformsToProtocol:@protocol(SimDeviceIOPortInterface)]) {
      continue;
    }
    id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> descriptor = [port descriptor];
    if (![descriptor conformsToProtocol:@protocol(SimDisplayRenderable)]) {
      continue;
    }
    if (![descriptor conformsToProtocol:@protocol(SimDisplayIOSurfaceRenderable)]) {
      continue;
    }
    if (![descriptor respondsToSelector:@selector(state)]) {
      [logger logFormat:@"SimDisplay %@ does not have a state, cannot determine if it is the main display", descriptor];
      continue;
    }
    id<SimDisplayDescriptorState> descriptorState = [descriptor performSelector:@selector(state)];
    unsigned short displayClass = descriptorState.displayClass;
    if (displayClass != 0) {
      [logger logFormat:@"SimDisplay Class is '%d' which is not the main display '0'", displayClass];
      continue;
    }
    return [[FBFramebuffer_Legacy alloc] initWithSurface:descriptor logger:logger];
  }
  return [[FBSimulatorError
    describeFormat:@"Could not find the Main Screen Surface for Clients %@ in %@", [FBCollectionInformation oneLineDescriptionFromArray:ioClient.ioPorts], ioClient]
    fail:error];
}

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  if (!self) {
    return nil;
  }

  _consumers = [NSMapTable
    mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
    valueOptions:NSPointerFunctionsCopyIn];
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (nullable IOSurface *)attachConsumer:(id<FBFramebufferConsumer>)consumer onQueue:(dispatch_queue_t)queue
{
  // Don't attach the same consumer twice
  NSAssert(![self isConsumerAttached:consumer], @"Cannot re-attach the same consumer %@", consumer);
  NSUUID *consumerUUID = NSUUID.UUID;

  // Attempt to return the surface synchronously (if supported).
  IOSurface *surface = [self extractImmediatelyAvailableSurface];

  // Register the consumer.
  [self.consumers setObject:consumerUUID forKey:consumer];
  [self registerConsumer:consumer uuid:consumerUUID queue:queue];

  return surface;
}

- (void)detachConsumer:(id<FBFramebufferConsumer>)consumer
{
  NSUUID *uuid = [self.consumers objectForKey:consumer];
  if (!uuid) {
    return;;
  }
  [self.consumers removeObjectForKey:consumer];
  [self unregisterConsumer:consumer uuid:uuid];
}

- (BOOL)isConsumerAttached:(id<FBFramebufferConsumer>)consumer
{
  for (id<FBFramebufferConsumer> existing_consumer in self.consumers.keyEnumerator) {
    if (existing_consumer == consumer) {
      return true;
    }
  }
  return false;
}

#pragma mark Private

- (IOSurface *)extractImmediatelyAvailableSurface
{
  return nil;
}

- (void)registerConsumer:(id<FBFramebufferConsumer>)consumer uuid:(NSUUID *)uuid queue:(dispatch_queue_t)queue
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)unregisterConsumer:(id<FBFramebufferConsumer>)consumer uuid:(NSUUID *)uuid
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

@end

@implementation FBFramebuffer_Legacy

- (instancetype)initWithSurface:(id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable>)surface logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithLogger:logger];
  if (!self) {
    return nil;
  }

  _surface = surface;

  return self;
}

- (IOSurface *)extractImmediatelyAvailableSurface
{
  IOSurface *framebufferSurface = self.surface.framebufferSurface;
  if (framebufferSurface) {
    return framebufferSurface;
  }
  return self.surface.ioSurface;
}

- (void)registerConsumer:(id<FBFramebufferConsumer>)consumer uuid:(NSUUID *)uuid queue:(dispatch_queue_t)queue
{
  void (^ioSurfaceChanged)(IOSurface *) = ^void(IOSurface *surface) {
    dispatch_async(queue, ^{
      [consumer didChangeIOSurface:surface];
    });
  };

  [self.surface registerCallbackWithUUID:uuid ioSurfacesChangeCallback:ioSurfaceChanged];
  [self.surface registerCallbackWithUUID:uuid ioSurfaceChangeCallback:ioSurfaceChanged];

  [self.surface registerCallbackWithUUID:uuid damageRectanglesCallback:^(NSArray<NSValue *> *frames) {
    dispatch_async(queue, ^{
      for (NSValue *value in frames) {
        [consumer didReceiveDamageRect:value.rectValue];
      }
    });
  }];
}

- (void)unregisterConsumer:(id<FBFramebufferConsumer>)consumer uuid:(NSUUID *)uuid
{
  [self.surface unregisterIOSurfacesChangeCallbackWithUUID:uuid];
  [self.surface unregisterIOSurfaceChangeCallbackWithUUID:uuid];

  [self.surface unregisterDamageRectanglesCallbackWithUUID:uuid];
}

@end
