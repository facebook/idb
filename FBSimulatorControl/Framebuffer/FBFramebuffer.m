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

static const CFTimeInterval FBFramebufferStatsLogIntervalSeconds = 5.0;

typedef struct {
    NSUInteger damageCallbackCount;
    NSUInteger damageRectCount;
    NSUInteger emptyDamageCallbackCount;
    NSUInteger ioSurfaceChangeCount;
} FBFramebufferStats;

@interface FBFramebuffer ()

@property (nonatomic, strong, readonly) NSMapTable<id<FBFramebufferConsumer>, NSUUID *> *consumers;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> surface;

@property (nonatomic, assign) FBFramebufferStats stats;
@property (nonatomic, assign) FBFramebufferStats lastLoggedStats;
@property (nonatomic, assign) CFAbsoluteTime statsStartTime;
@property (nonatomic, assign) CFAbsoluteTime lastStatsLogTime;

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
    return [[FBFramebuffer alloc] initWithSurface:descriptor logger:logger];
  }
  return [[FBSimulatorError
    describeFormat:@"Could not find the Main Screen Surface for Clients %@ in %@", [FBCollectionInformation oneLineDescriptionFromArray:ioClient.ioPorts], ioClient]
    fail:error];
}

- (instancetype)initWithSurface:(id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable>)surface logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumers = [NSMapTable
    mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
    valueOptions:NSPointerFunctionsCopyIn];
  _logger = logger;
  _surface = surface;

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
  IOSurface *framebufferSurface = self.surface.framebufferSurface;
  if (framebufferSurface) {
    return framebufferSurface;
  }
  return self.surface.ioSurface;
}

- (void)registerConsumer:(id<FBFramebufferConsumer>)consumer uuid:(NSUUID *)uuid queue:(dispatch_queue_t)queue
{
  void (^ioSurfaceChanged)(IOSurface *) = ^void(IOSurface *surface) {
    FBFramebufferStats s = self.stats;
    s.ioSurfaceChangeCount += 1;
    self.stats = s;
    if (s.ioSurfaceChangeCount == 1) {
      [self.logger.info logFormat:@"First IOSurface change callback, surface=%@", surface];
    }
    dispatch_async(queue, ^{
      [consumer didChangeIOSurface:surface];
    });
  };

  [self.surface registerCallbackWithUUID:uuid ioSurfacesChangeCallback:ioSurfaceChanged];
  [self.surface registerCallbackWithUUID:uuid ioSurfaceChangeCallback:ioSurfaceChanged];

  [self.surface registerCallbackWithUUID:uuid damageRectanglesCallback:^(NSArray<NSValue *> *frames) {
    FBFramebufferStats s = self.stats;
    s.damageCallbackCount += 1;
    s.damageRectCount += frames.count;
    if (frames.count == 0) {
      s.emptyDamageCallbackCount += 1;
    }
    self.stats = s;
    [self logStatsIfNeeded];
    dispatch_async(queue, ^{
      [consumer didReceiveDamageRect];
    });
  }];
}

- (void)logStatsIfNeeded
{
  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  if (self.statsStartTime == 0) {
    self.statsStartTime = now;
    self.lastStatsLogTime = now;
    [self.logger.info logFormat:@"First damage callback received"];
    return;
  }
  if (now - self.lastStatsLogTime < FBFramebufferStatsLogIntervalSeconds) {
    return;
  }
  CFTimeInterval intervalDuration = now - self.lastStatsLogTime;
  self.lastStatsLogTime = now;

  FBFramebufferStats current = self.stats;
  FBFramebufferStats last = self.lastLoggedStats;
  NSUInteger intervalCallbacks = current.damageCallbackCount - last.damageCallbackCount;
  NSUInteger intervalRects = current.damageRectCount - last.damageRectCount;
  NSUInteger intervalEmpty = current.emptyDamageCallbackCount - last.emptyDamageCallbackCount;
  NSUInteger intervalIOSurface = current.ioSurfaceChangeCount - last.ioSurfaceChangeCount;
  self.lastLoggedStats = current;

  double intervalRate = intervalDuration > 0 ? (double)intervalCallbacks / intervalDuration : 0;
  CFTimeInterval totalElapsed = now - self.statsStartTime;
  double totalRate = totalElapsed > 0 ? (double)current.damageCallbackCount / totalElapsed : 0;

  [self.logger.info logFormat:
    @"Framebuffer stats (interval): %lu damage callbacks in %.1fs (%.1f/s, %lu rects, %lu empty) — %lu IOSurface changes",
    (unsigned long)intervalCallbacks,
    intervalDuration,
    intervalRate,
    (unsigned long)intervalRects,
    (unsigned long)intervalEmpty,
    (unsigned long)intervalIOSurface];
  [self.logger.info logFormat:
    @"Framebuffer stats (total): %lu damage callbacks in %.1fs (%.1f/s, %lu rects, %lu empty) — %lu IOSurface changes",
    (unsigned long)current.damageCallbackCount,
    totalElapsed,
    totalRate,
    (unsigned long)current.damageRectCount,
    (unsigned long)current.emptyDamageCallbackCount,
    (unsigned long)current.ioSurfaceChangeCount];
}

- (void)unregisterConsumer:(id<FBFramebufferConsumer>)consumer uuid:(NSUUID *)uuid
{
  [self.surface unregisterIOSurfacesChangeCallbackWithUUID:uuid];
  [self.surface unregisterIOSurfaceChangeCallbackWithUUID:uuid];

  [self.surface unregisterDamageRectanglesCallbackWithUUID:uuid];
}

@end
