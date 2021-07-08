/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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

@interface FBFramebuffer_Queue_Forwarder : NSObject

@property (nonatomic, weak, readonly) id<FBFramebufferConsumer> consumer;
@property (nonatomic, strong, readonly) dispatch_queue_t consumerQueue;
@property (nonatomic, strong, readwrite) NSUUID *consumerUUID;

@end

@implementation FBFramebuffer_Queue_Forwarder

- (instancetype)initWithConsumer:(id<FBFramebufferConsumer>)consumer consumerQueue:(dispatch_queue_t)consumerQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _consumerQueue = consumerQueue;
  _consumerUUID = NSUUID.UUID;

  return self;
}

- (void)didChangeIOSurface:(IOSurface *)surface
{
  id<FBFramebufferConsumer> consumer = self.consumer;
  dispatch_async(self.consumerQueue, ^{
    [consumer didChangeIOSurface:surface];
  });
}

- (void)didReceiveDamageRect:(CGRect)rect
{
  id<FBFramebufferConsumer> consumer = self.consumer;
  dispatch_async(self.consumerQueue, ^{
    [consumer didReceiveDamageRect:rect];
  });
}

- (NSString *)consumerIdentifier
{
  return self.consumer.consumerIdentifier;
}

@end

@interface FBFramebuffer ()

@property (nonatomic, strong, readonly) NSMapTable<id<FBFramebufferConsumer>, id> *forwarders;
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
  NSMapTable<id<FBFramebufferConsumer>, id> *forwarders = [NSMapTable
    mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
    valueOptions:NSPointerFunctionsStrongMemory];

  _forwarders = forwarders;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (nullable IOSurface *)attachConsumer:(id<FBFramebufferConsumer>)consumer onQueue:(dispatch_queue_t)queue
{
  // Don't attach the same consumer twice
  FBFramebuffer_Queue_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
  NSAssert(forwarder == nil, @"Cannot re-attach the same consumer %@", forwarder.consumer);

  // Create the forwarder and keep a reference to it.
  forwarder = [[FBFramebuffer_Queue_Forwarder alloc] initWithConsumer:consumer consumerQueue:queue];
  [self.forwarders setObject:forwarder forKey:consumer];

  // Attempt to return the surface synchronously (if supported).
  IOSurface *surface = [self extractImmediatelyAvailableSurface];

  // Register the consumer.
  [self registerConsumer:consumer withForwarder:forwarder];

  return surface;
}

- (void)detachConsumer:(id<FBFramebufferConsumer>)consumer
{
  FBFramebuffer_Queue_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
  if (!forwarder) {
    return;
  }
  [self detachConsumer:consumer fromForwarder:forwarder];
}

- (NSArray<id<FBFramebufferConsumer>> *)attachedConsumers
{
  NSMutableArray<id<FBFramebufferConsumer>> *consumers = [NSMutableArray array];
  for (id<FBFramebufferConsumer> consumer in self.forwarders.keyEnumerator) {
    [consumers addObject:consumer];
  }
  return [consumers copy];
}

- (BOOL)isConsumerAttached:(id<FBFramebufferConsumer>)consumer
{
  return [[self attachedConsumers] containsObject:consumer];
}

#pragma mark Private

- (IOSurface *)extractImmediatelyAvailableSurface
{
  return nil;
}

- (void)registerConsumer:(id<FBFramebufferConsumer>)consumer withForwarder:(FBFramebuffer_Queue_Forwarder *)forwarder
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)detachConsumer:(id<FBFramebufferConsumer>)consumer fromForwarder:(FBFramebuffer_Queue_Forwarder *)forwarder
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
  return self.surface.ioSurface;
}

- (void)registerConsumer:(id<FBFramebufferConsumer>)consumer withForwarder:(FBFramebuffer_Queue_Forwarder *)forwarder
{
  [self.surface registerCallbackWithUUID:forwarder.consumerUUID ioSurfaceChangeCallback:^(IOSurface *surface) {
    [forwarder didChangeIOSurface:surface];
  }];
  [self.surface registerCallbackWithUUID:forwarder.consumerUUID damageRectanglesCallback:^(NSArray<NSValue *> *frames) {
    for (NSValue *value in frames) {
      [forwarder didReceiveDamageRect:value.rectValue];
    }
  }];
}

- (void)detachConsumer:(id<FBFramebufferConsumer>)consumer fromForwarder:(FBFramebuffer_Queue_Forwarder *)forwarder
{
  [self.surface unregisterIOSurfaceChangeCallbackWithUUID:forwarder.consumerUUID];
  [self.surface unregisterDamageRectanglesCallbackWithUUID:forwarder.consumerUUID];
}

@end
