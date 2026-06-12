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

// Xcode 27+ SimulatorKit (Swift rewrite): displays are vended via these
// reverse-engineered, Objective-C-callable protocols instead of the legacy
// SimDisplayRenderable / SimDisplayIOSurfaceRenderable surface protocols.
#import <SimulatorKit/SimScreenAdapter-Protocol.h>
#import <SimulatorKit/SimScreen-Protocol.h>
#import <SimulatorKit/SimScreenProperties-Protocol.h>

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

@interface FBFramebuffer_Screen : FBFramebuffer

@property (nonatomic, strong, readonly) id<SimScreen> screen;

- (instancetype)initWithScreen:(id<SimScreen>)screen logger:(id<FBControlCoreLogger>)logger;

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
    id descriptor = [port descriptor];

    // Xcode 27+: SimulatorKit was rewritten in Swift and the headless IOSurface
    // path moved to the SimScreenAdapter / SimScreen protocols. Prefer this when
    // the descriptor conforms (runtime feature-detection, no version sniffing).
    if ([descriptor conformsToProtocol:@protocol(SimScreenAdapter)]) {
      id<SimScreen> screen = [self defaultScreenForAdapter:(id<SimScreenAdapter>)descriptor logger:logger];
      if (screen) {
        return [[FBFramebuffer_Screen alloc] initWithScreen:screen logger:logger];
      }
      [logger logFormat:@"SimScreenAdapter %@ did not vend a usable screen, continuing", descriptor];
      continue;
    }

    // Xcode <= 26: legacy SimDisplayRenderable / SimDisplayIOSurfaceRenderable path.
    if (![descriptor conformsToProtocol:@protocol(SimDisplayRenderable)]) {
      continue;
    }
    if (![descriptor conformsToProtocol:@protocol(SimDisplayIOSurfaceRenderable)]) {
      continue;
    }
    id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> legacyDescriptor = descriptor;
    if (![legacyDescriptor respondsToSelector:@selector(state)]) {
      [logger logFormat:@"SimDisplay %@ does not have a state, cannot determine if it is the main display", legacyDescriptor];
      continue;
    }
    id<SimDisplayDescriptorState> descriptorState = [legacyDescriptor performSelector:@selector(state)];
    unsigned short displayClass = descriptorState.displayClass;
    if (displayClass != 0) {
      [logger logFormat:@"SimDisplay Class is '%d' which is not the main display '0'", displayClass];
      continue;
    }
    return [[FBFramebuffer_Legacy alloc] initWithSurface:legacyDescriptor logger:logger];
  }
  return [[FBSimulatorError
    describeFormat:@"Could not find the Main Screen Surface for Clients %@ in %@", [FBCollectionInformation oneLineDescriptionFromArray:ioClient.ioPorts], ioClient]
    fail:error];
}

/**
 Synchronously resolves the default `SimScreen` from a `SimScreenAdapter`.

 `+mainScreenSurfaceForSimulator:` is a synchronous factory, but the Xcode 27
 enumeration API is asynchronous, so we bridge it with a bounded semaphore wait.
 */
+ (id<SimScreen>)defaultScreenForAdapter:(id<SimScreenAdapter>)adapter logger:(id<FBControlCoreLogger>)logger
{
  if (![adapter respondsToSelector:@selector(enumerateScreensWithCompletionQueue:completionHandler:)]) {
    [logger logFormat:@"SimScreenAdapter %@ does not respond to enumerateScreensWithCompletionQueue:completionHandler:", adapter];
    return nil;
  }

  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.framebuffer.screenenumeration", DISPATCH_QUEUE_SERIAL);
  __block id<SimScreen> resolvedScreen = nil;

  [adapter enumerateScreensWithCompletionQueue:queue completionHandler:^(NSArray<id<SimScreen>> *screens, NSError *enumerationError) {
    if (enumerationError) {
      [logger logFormat:@"Failed to enumerate SimScreens: %@", enumerationError];
    }
    for (id<SimScreen> screen in screens) {
      if ([screen respondsToSelector:@selector(isDefault)] && screen.isDefault) {
        resolvedScreen = screen;
        break;
      }
    }
    if (!resolvedScreen) {
      resolvedScreen = screens.firstObject;
    }
    dispatch_semaphore_signal(semaphore);
  }];

  if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC))) != 0) {
    [logger logFormat:@"Timed out waiting for SimScreenAdapter %@ to enumerate screens", adapter];
    return nil;
  }
  return resolvedScreen;
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
//  [self.surface registerCallbackWithUUID:uuid ioSurfaceChangeCallback:ioSurfaceChanged];

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
//  [self.surface unregisterIOSurfaceChangeCallbackWithUUID:uuid];

  [self.surface unregisterDamageRectanglesCallbackWithUUID:uuid];
}

@end

@implementation FBFramebuffer_Screen

- (instancetype)initWithScreen:(id<SimScreen>)screen logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithLogger:logger];
  if (!self) {
    return nil;
  }

  _screen = screen;

  return self;
}

- (IOSurface *)extractImmediatelyAvailableSurface
{
  IOSurface *unmaskedSurface = self.screen.unmaskedSurface;
  if (unmaskedSurface) {
    return unmaskedSurface;
  }
  return self.screen.maskedSurface;
}

- (void)registerConsumer:(id<FBFramebufferConsumer>)consumer uuid:(NSUUID *)uuid queue:(dispatch_queue_t)queue
{
  [self.screen
    registerScreenCallbacksWithUUID:uuid
    callbackQueue:queue
    frameCallback:^{}
    surfacesChangedCallback:^(IOSurface *unmaskedSurface, IOSurface *maskedSurface) {
      // Prefer the raw (unmasked) surface to mirror the legacy framebufferSurface.
      IOSurface *surface = unmaskedSurface ?: maskedSurface;
      dispatch_async(queue, ^{
        [consumer didChangeIOSurface:surface];
      });
    }
    propertiesChangedCallback:^(id<SimScreenProperties> properties) {}];
}

- (void)unregisterConsumer:(id<FBFramebufferConsumer>)consumer uuid:(NSUUID *)uuid
{
  if ([self.screen respondsToSelector:@selector(unregisterScreenCallbacksWithUUID:)]) {
    [self.screen unregisterScreenCallbacksWithUUID:uuid];
  }
}

@end
