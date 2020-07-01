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

#import "FBSimulatorError.h"

static IOSurfaceRef extractSurfaceFromUnknown(id unknown)
{
  // Return the Surface Immediately, if one is immediately available.
  if (!unknown) {
    return nil;
  }
  // If the object returns an
  if (CFGetTypeID((__bridge CFTypeRef)(unknown)) == IOSurfaceGetTypeID()) {
    return (__bridge IOSurfaceRef)(unknown);
  }

  // We need to convert the surface, treat it as an xpc_object_t
  xpc_object_t xpcObject = unknown;
  IOSurfaceRef surface = IOSurfaceLookupFromXPCObject(xpcObject);
  if (!surface) {
    return nil;
  }
  CFAutorelease(surface);
  return surface;
}

@interface FBFramebuffer_IOClient_Forwarder : NSObject <SimDisplayDamageRectangleDelegate, SimDisplayIOSurfaceRenderableDelegate, SimDeviceIOPortConsumer>

@property (nonatomic, weak, readonly) id<FBFramebufferConsumer> consumer;
@property (nonatomic, strong, readonly) dispatch_queue_t consumerQueue;
@property (nonatomic, strong, readwrite) NSUUID *consumerUUID;

@end

@implementation FBFramebuffer_IOClient_Forwarder

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

- (void)didChangeIOSurface:(nullable id)unknown
{
  IOSurfaceRef surface = extractSurfaceFromUnknown(unknown);
  if (!surface) {
    [self.consumer didChangeIOSurface:NULL];
    return;
  }
  // Ensure the Surface is retained as it is delivered asynchronously.
  id<FBFramebufferConsumer> consumer = self.consumer;
  CFRetain(surface);
  dispatch_async(self.consumerQueue, ^{
    [consumer didChangeIOSurface:surface];
    CFRelease(surface);
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

@interface FBFramebuffer_SimDeviceFramebufferService_Forwarder : NSObject

@property (nonatomic, weak, readonly) id<FBFramebufferConsumer> consumer;

@end

@implementation FBFramebuffer_SimDeviceFramebufferService_Forwarder

- (instancetype)initWithConsumer:(id<FBFramebufferConsumer>)consumer
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

@interface FBFramebuffer ()

@property (nonatomic, strong, readonly) NSMapTable<id<FBFramebufferConsumer>, id> *forwarders;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@interface FBFramebuffer_IOClient : FBFramebuffer

@property (nonatomic, strong, readonly) id<SimDeviceIOProtocol> ioClient;
@property (nonatomic, strong, readonly) id<SimDeviceIOPortInterface> port;
@property (nonatomic, strong, readonly) id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> surface;

- (instancetype)initWithIOClient:(id<SimDeviceIOProtocol>)ioClient port:(id<SimDeviceIOPortInterface>)port surface:(id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable>)surface logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_FramebufferService : FBFramebuffer

@property (nonatomic, strong, readonly) SimDeviceFramebufferService *framebufferService;
@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService logger:(id<FBControlCoreLogger>)logger;

@end

@implementation FBFramebuffer

#pragma mark Initializers

+ (nullable instancetype)mainScreenSurfaceForClient:(id<SimDeviceIOProtocol>)ioClient logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
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
    return [[FBFramebuffer_IOClient alloc] initWithIOClient:ioClient port:port surface:descriptor logger:logger];
  }
  return [[FBSimulatorError
    describeFormat:@"Could not find the Main Screen Surface for Clients %@ in %@", [FBCollectionInformation oneLineDescriptionFromArray:ioClient.ioPorts], ioClient]
    fail:error];
}

+ (instancetype)mainScreenSurfaceForFramebufferService:(SimDeviceFramebufferService *)framebufferService logger:(id<FBControlCoreLogger>)logger
{
  return [[FBFramebuffer_FramebufferService alloc] initWithFramebufferService:framebufferService logger:logger];
}

- (instancetype)initWithForwarders:(NSMapTable<id<FBFramebufferConsumer>, id> *)forwarders logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _forwarders = forwarders;
  _logger = logger;

  return self;
}

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  NSMapTable<id<FBFramebufferConsumer>, id> *forwarders = [NSMapTable
    mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
    valueOptions:NSPointerFunctionsStrongMemory];
  return [self initWithForwarders:forwarders logger:logger];
}

#pragma mark Public Methods

- (nullable IOSurfaceRef)attachConsumer:(id<FBFramebufferConsumer>)consumer onQueue:(dispatch_queue_t)queue
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (void)detachConsumer:(id<FBFramebufferConsumer>)consumer
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
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

#pragma mark FBJSONSerialization

- (id)jsonSerializableRepresentation
{
  return @{};
}

@end

@implementation FBFramebuffer_IOClient

- (instancetype)initWithIOClient:(id<SimDeviceIOProtocol>)ioClient port:(id<SimDeviceIOPortInterface>)port surface:(id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable>)surface logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithLogger:logger];
  if (!self) {
    return nil;
  }

  _ioClient = ioClient;
  _port = port;
  _surface = surface;

  return self;
}

- (nullable IOSurfaceRef)attachConsumer:(id<FBFramebufferConsumer>)consumer onQueue:(dispatch_queue_t)queue
{
  // Don't attach the same consumer twice
  FBFramebuffer_IOClient_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
  NSAssert(forwarder == nil, @"Cannot re-attach the same consumer %@", forwarder.consumer);

  // Create the forwarder and keep a reference to it.
  forwarder = [[FBFramebuffer_IOClient_Forwarder alloc] initWithConsumer:consumer consumerQueue:queue];
  [self.forwarders setObject:forwarder forKey:consumer];

  // Extract the IOSurface if one does not exist.
  IOSurfaceRef surface = extractSurfaceFromUnknown(self.surface.ioSurface);

  // Register the consumer.
  if ([self.ioClient respondsToSelector:@selector(attachConsumer:withUUID:toPort:errorQueue:errorHandler:)]) {
    [self.ioClient attachConsumer:forwarder withUUID:forwarder.consumerUUID toPort:self.port errorQueue:queue errorHandler:^(NSError *error){}];
  } else if ([self.ioClient respondsToSelector:@selector(attachConsumer:toPort:)]) {
    [self.ioClient attachConsumer:forwarder toPort:self.port];
  } else {
    [self.surface registerCallbackWithUUID:forwarder.consumerUUID ioSurfaceChangeCallback:^(id next) {
      [forwarder didChangeIOSurface:next];
    }];
    [self.surface registerCallbackWithUUID:forwarder.consumerUUID damageRectanglesCallback:^(NSArray<NSValue *> *rects) {
      for (NSValue *value in rects) {
        [forwarder didReceiveDamageRect:value.rectValue];
      }
    }];
  }

  return surface;
}

- (void)detachConsumer:(id<FBFramebufferConsumer>)consumer
{
  FBFramebuffer_IOClient_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
  if (!forwarder) {
    return;
  }
  if ([self.ioClient respondsToSelector:@selector(detachConsumer:fromPort:)]) {
    [self.ioClient detachConsumer:forwarder fromPort:self.port];
  } else {
    [self.surface unregisterIOSurfaceChangeCallbackWithUUID:forwarder.consumerUUID];
    [self.surface unregisterDamageRectanglesCallbackWithUUID:forwarder.consumerUUID];
  }
}

- (CGRect)fullDamageRect
{
  CGSize size = self.surface.displaySize;
  return CGRectMake(0, 0, size.width, size.height);
}

@end

@implementation FBFramebuffer_FramebufferService

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithLogger:logger];
  if (!self) {
    return nil;
  }

  _framebufferService = framebufferService;

  return self;
}

- (nullable IOSurfaceRef)attachConsumer:(id<FBFramebufferConsumer>)consumer onQueue:(dispatch_queue_t)queue
{
  // Don't attach the same consumer twice
  FBFramebuffer_SimDeviceFramebufferService_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
  NSAssert(forwarder == nil, @"Cannot re-attach the same consumer %@", forwarder.consumer);

  // Create the forwarder and keep a reference to it.
  forwarder = [[FBFramebuffer_SimDeviceFramebufferService_Forwarder alloc] initWithConsumer:consumer];
  [self.forwarders setObject:forwarder forKey:consumer];

  // Register for the callbacks.
  [self.framebufferService registerClient:forwarder onQueue:self.clientQueue];

  // We can't synchronously fetch a surface here.
  return nil;
}

- (void)detachConsumer:(id<FBFramebufferConsumer>)consumer
{
  FBFramebuffer_SimDeviceFramebufferService_Forwarder *forwarder = [self.forwarders objectForKey:consumer];
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
    if ([FBXcodeConfiguration.xcodeVersionNumber isLessThan:[NSDecimalNumber decimalNumberWithString:@"8.1"]]) {
      [self.framebufferService invalidate];
    }
  }
}

@end
