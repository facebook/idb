/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferSurface.h"

#import <CoreSimulator/SimDeviceIOClient.h>

#import <xpc/xpc.h>

#import <IOSurface/IOSurface.h>

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderable-Protocol.h>
#import <SimulatorKit/SimDisplayRenderable-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayDescriptorState-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortConsumer-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortDescriptorState-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderable-Protocol.h>
#import <SimulatorKit/SimDisplayRenderable-Protocol.h>

@interface FBFramebufferSurface_IOClient_Forwarder : NSObject <SimDisplayDamageRectangleDelegate, SimDisplayIOSurfaceRenderableDelegate, SimDeviceIOPortConsumer>

@property (nonatomic, weak, readonly) id<FBFramebufferSurfaceConsumer> consumer;
@property (nonatomic, strong, readwrite) NSUUID *consumerUUID;

@end

@implementation FBFramebufferSurface_IOClient_Forwarder

- (instancetype)initWithConsumer:(id<FBFramebufferSurfaceConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _consumerUUID = NSUUID.UUID;

  return self;
}

- (void)didChangeIOSurface:(nullable xpc_object_t)xpcSurface
{
  if (!xpcSurface) {
    [self.consumer didChangeIOSurface:NULL];
    return;
  }
  IOSurfaceRef surface = IOSurfaceLookupFromXPCObject(xpcSurface);
  [self.consumer didChangeIOSurface:surface];
  CFRelease(surface);
}

- (void)didReceiveDamageRect:(CGRect)rect
{
  [self.consumer didReceiveDamageRect:rect];
}

- (NSString *)consumerIdentifier
{
  return self.consumer.consumerIdentifier;
}

@end

@interface FBFramebufferSurface_SimDeviceFramebufferService_Forwarder : NSObject

@property (nonatomic, weak, readonly) id<FBFramebufferSurfaceConsumer> consumer;

@end

@implementation FBFramebufferSurface_SimDeviceFramebufferService_Forwarder

- (instancetype)initWithConsumer:(id<FBFramebufferSurfaceConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;

  return self;
}

- (void)setIOSurface:(IOSurfaceRef)surface
{
  [self.consumer didChangeIOSurface:surface];
}

@end

@interface FBFramebufferSurface ()

@property (nonatomic, strong, readonly) NSMapTable<id<FBFramebufferSurfaceConsumer>, id> *forwarders;

@end

@interface FBFramebufferSurface_IOClient : FBFramebufferSurface

@property (nonatomic, strong, readonly) SimDeviceIOClient *ioClient;
@property (nonatomic, strong, readonly) id<SimDeviceIOPortInterface> port;
@property (nonatomic, strong, readonly) id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> surface;

- (instancetype)initWithIOClient:(SimDeviceIOClient *)ioClient port:(id<SimDeviceIOPortInterface>)port surface:(id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable>)surface;

@end

@interface FBFramebufferSurface_FramebufferService : FBFramebufferSurface

@property (nonatomic, strong, readonly) SimDeviceFramebufferService *framebufferService;
@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService clientQueue:(dispatch_queue_t)clientQueue;

@end

@implementation FBFramebufferSurface

#pragma mark Initializers

+ (nullable instancetype)mainScreenSurfaceForClient:(SimDeviceIOClient *)ioClient
{
  for (id<SimDeviceIOPortInterface> port in ioClient.ioPorts) {
    if (![port conformsToProtocol:@protocol(SimDeviceIOPortInterface)]) {
      continue;
    }
    id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> surface = (id) [port descriptor];
    if (![surface conformsToProtocol:@protocol(SimDisplayRenderable)]) {
      continue;
    }
    if (![surface conformsToProtocol:@protocol(SimDisplayIOSurfaceRenderable)]) {
      continue;
    }
    return [[FBFramebufferSurface_IOClient alloc] initWithIOClient:ioClient port:port surface:surface];
  }
  return nil;
}

+ (instancetype)mainScreenSurfaceForFramebufferService:(SimDeviceFramebufferService *)framebufferService clientQueue:(dispatch_queue_t)clientQueue
{
  return [[FBFramebufferSurface_FramebufferService alloc] initWithFramebufferService:framebufferService clientQueue:clientQueue];
}

- (instancetype)initWithForwarders:(NSMapTable<id<FBFramebufferSurfaceConsumer>, id> *)forwarders
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _forwarders = forwarders;

  return self;
}

- (instancetype)init
{
  NSMapTable<id<FBFramebufferSurfaceConsumer>, id> *forwarders = [NSMapTable
    mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
    valueOptions:NSPointerFunctionsStrongMemory];
  return [self initWithForwarders:forwarders];
}

#pragma mark Public Methods

- (void)attachConsumer:(id<FBFramebufferSurfaceConsumer>)consumer
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)detachConsumer:(id<FBFramebufferSurfaceConsumer>)consumer
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (NSArray<id<FBFramebufferSurfaceConsumer>> *)attachedConsumers
{
  NSMutableArray<id<FBFramebufferSurfaceConsumer>> *consumers = [NSMutableArray array];
  for (id<FBFramebufferSurfaceConsumer> consumer in self.forwarders.keyEnumerator) {
    [consumers addObject:consumer];
  }
  return [consumers copy];
}

@end

@implementation FBFramebufferSurface_IOClient

- (instancetype)initWithIOClient:(SimDeviceIOClient *)ioClient port:(id<SimDeviceIOPortInterface>)port surface:(id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable>)surface
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _ioClient = ioClient;
  _port = port;
  _surface = surface;

  return self;
}

- (void)attachConsumer:(id<FBFramebufferSurfaceConsumer>)consumer
{
  // Don't attach the same consumer twice
  FBFramebufferSurface_IOClient_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
  NSAssert(forwarder == nil, @"Cannot re-attach the same consumer %@", forwarder.consumer);

  // Create the forwarder and keep a reference to it.
  forwarder = [[FBFramebufferSurface_IOClient_Forwarder alloc] initWithConsumer:consumer];
  [self.forwarders setObject:forwarder forKey:consumer];

  // The Port *must* be retained, otherwise the delegate will not be notified of changes to the Damage Rect.
  // The Damage rect is essential for video encoding.
  [forwarder didChangeIOSurface:self.surface.ioSurface];
  // simctl in Xcode 8.2 does not send the damage rect immediately, which means video encoding will start on the first change to the frame.
  // However, we want to immedately start as soon as the surface is available. In this case we say the whole rect is damaged for it to be rendered.
  [forwarder didReceiveDamageRect:self.fullDamageRect];
  // Actually register the consumer.
  [self.ioClient attachConsumer:forwarder toPort:self.port];
}

- (void)detachConsumer:(id<FBFramebufferSurfaceConsumer>)consumer
{
  FBFramebufferSurface_IOClient_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
  if (!consumer) {
    return;
  }
  [self.ioClient detachConsumer:forwarder fromPort:self.port];
}

- (CGRect)fullDamageRect
{
  CGSize size = self.surface.displaySize;
  return CGRectMake(0, 0, size.width, size.height);
}

@end

@implementation FBFramebufferSurface_FramebufferService

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

- (void)attachConsumer:(id<FBFramebufferSurfaceConsumer>)consumer
{
  // Don't attach the same consumer twice
  FBFramebufferSurface_SimDeviceFramebufferService_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
  NSAssert(forwarder == nil, @"Cannot re-attach the same consumer %@", forwarder.consumer);

  // Create the forwarder and keep a reference to it.
  forwarder = [[FBFramebufferSurface_SimDeviceFramebufferService_Forwarder alloc] initWithConsumer:consumer];
  [self.forwarders setObject:forwarder forKey:consumer];

  // Register for the callbacks.
  [self.framebufferService registerClient:forwarder onQueue:self.clientQueue];
}

- (void)detachConsumer:(id<FBFramebufferSurfaceConsumer>)consumer
{
  FBFramebufferSurface_SimDeviceFramebufferService_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
  if (!consumer) {
    return;
  }
  // Remove the forwarder, we have a strong reference to the consumer.
  [self.forwarders removeObjectForKey:consumer];

  // Unregister the client
  [self.framebufferService unregisterClient:forwarder];
  // Only call invalidate if the selector exists.
  if ([self.framebufferService respondsToSelector:@selector(invalidate)]) {
    // The call to this method has been dropped in Xcode 8.1, but exists in Xcode 8.0
    // Don't call it on Xcode 8.1
    if ([FBControlCoreGlobalConfiguration.xcodeVersionNumber isLessThan:[NSDecimalNumber decimalNumberWithString:@"8.1"]]) {
      [self.framebufferService invalidate];
    }
  }
}

@end
