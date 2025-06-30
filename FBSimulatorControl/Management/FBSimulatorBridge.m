/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorBridge.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

static NSString *const KeyAXTraits = @"AXTraits";
static NSString *const KeyTraits = @"traits";
static NSString *const KeyType = @"type";

static NSTimeInterval BridgeReadyTimeout = 5.0;

@interface FBSimulatorBridge ()

@property (nonatomic, strong, nullable, readwrite) NSProxy<SimulatorBridge> *bridge;
@property (nonatomic, strong, nullable, readwrite) FBProcess *process;
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;
@property (nonatomic, strong, readonly) dispatch_queue_t asyncQueue;

@end

@implementation FBSimulatorBridge

#pragma mark Initializers

+ (dispatch_queue_t)createBridgeQueue
{
  return dispatch_queue_create("com.facebook.fbsimulatorcontrol.bridge", DISPATCH_QUEUE_SERIAL);
}

+ (NSString *)simulatorBridgeLaunchPathWithError:(NSError **)error
{
  FBBundleDescriptor *simulatorApp = FBXcodeConfiguration.simulatorApp;
  if (FBXcodeConfiguration.isXcode12_5OrGreater) {
    return [[FBControlCoreError
      describe:@"Some idb functionality is not yet available with Xcode 12.5, downgrade your Xcode version and try again."]
      fail:error];
  }
  NSString *path = [simulatorApp.path stringByAppendingPathComponent:@"Contents/Resources/Platforms/iphoneos/usr/libexec/SimulatorBridge"];
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:path error:error];
  if (!binary) {
    return nil;
  }
  return binary.path;
}

+ (FBFuture<id<SimulatorBridge>> *)bridgeForSimulator:(FBSimulator *)simulator
{
  // Connect to the expected-to-be-running CoreSimulatorBridge running inside the Simulator.
  // This mimics the behaviour of Simulator.app, which just looks up the service then connects to the distant object over a Remote Object connection.
  dispatch_queue_t bridgeQueue = FBSimulatorBridge.createBridgeQueue;
  dispatch_queue_t asyncQueue = simulator.asyncQueue;
  return [[[self
    bridgeProcessForSimulator:simulator]
    onQueue:simulator.workQueue map:^(NSArray<id> *tuple) {
      NSCParameterAssert(tuple.count >= 1);
      NSProxy<SimulatorBridge> *bridge = tuple[0];
      FBProcess *process = (tuple.count == 2) ? tuple[1] : nil;
      return [[FBSimulatorBridge alloc] initWithBridge:bridge process:process workQueue:bridgeQueue asyncQueue:asyncQueue];
    }]
    onQueue:bridgeQueue fmap:^(FBSimulatorBridge *bridge) {
      [simulator.logger logFormat:@"Enabling Accessibility on the bridge %@", bridge];
      return [[bridge enableAccessibility] mapReplace:bridge];
    }];
}

+ (FBFuture<NSArray<id> *> *)bridgeProcessForSimulator:(FBSimulator *)simulator;
{
  NSTimeInterval timeout = FBControlCoreGlobalConfiguration.fastTimeout;
  NSString *portName = [self portNameForSimulator:simulator];
  return [[self
    bridgeForSimulator:simulator portName:portName]
    onQueue:simulator.workQueue chain:^(FBFuture *future) {
      // If the Bridge Could not be Constructed, spawn the SimulatorBridge Process
      // Re-Attempt to obtain the SimulatorBridge Object at the same time, with a timeout
      if (future.error) {
        return [FBFuture futureWithFutures:@[
          [FBSimulatorBridge bridgeForSimulator:simulator portName:portName timeout:timeout],
          [FBSimulatorBridge bridgeOperationForSimulator:simulator portName:portName],
        ]];
      }
      // Otherwise just return the original future wrapped in the array.
      [simulator.logger logFormat:@"SimulatorBridge Agent %@ is already running for %@", future.result, portName];
      return [FBFuture futureWithFutures:@[future]];
    }];
}

static NSString *const SimulatorBridgePortSuffix = @"FBSimulatorControl";

+ (NSString *)portNameForSimulator:(FBSimulator *)simulator
{
  NSString *portName = @"com.apple.iphonesimulator.bridge";
  return [portName stringByAppendingFormat:@".%@", SimulatorBridgePortSuffix];
}

+ (FBFuture<FBProcess * > *)bridgeOperationForSimulator:(FBSimulator *)simulator portName:(NSString *)portName
{
  NSError *error = nil;
  NSString *bridgeLaunchPath = [self simulatorBridgeLaunchPathWithError:&error];
  if (!bridgeLaunchPath) {
    return [FBFuture futureWithError:error];
  }
  id<FBControlCoreLogger> logger = [simulator.logger withName:@"SimulatorBridge"];
  id<FBNotifyingBuffer> buffer = FBDataBuffer.notifyingBuffer;
  FBProcessIO *processIO = [[FBProcessIO alloc]
    initWithStdIn:nil
    stdOut:[FBProcessOutput outputForDataConsumer:buffer]
    stdErr:[FBProcessOutput outputForLogger:logger]];

  FBProcessSpawnConfiguration *config = [[FBProcessSpawnConfiguration alloc]
    initWithLaunchPath:bridgeLaunchPath
    arguments:@[portName]
    environment:@{}
    io:processIO
    mode:FBProcessSpawnModeDefault];

  [logger logFormat:@"Launching SimulatorBridge agent for %@", portName];
  return [[[simulator
    launchProcess:config]
    onQueue:simulator.asyncQueue fmap:^(FBProcess *process) {
      return [[[buffer
        consumeAndNotifyWhen:[@"READY" dataUsingEncoding:NSUTF8StringEncoding]]
        timeout:BridgeReadyTimeout waitingFor:@"The launched process %@ to specify 'READY' for %@", process, portName]
        mapReplace:process];
    }]
    onQueue:simulator.asyncQueue doOnResolved:^(FBProcess *process) {
      [logger logFormat:@"Bridge process is launched %@. %@ is now ready", process, portName];
    }];
}

+ (FBFuture<NSProxy<SimulatorBridge> *> *)bridgeForSimulator:(FBSimulator *)simulator portName:(NSString *)portName timeout:(NSTimeInterval)timeout
{
  return [[[FBFuture
    onQueue:simulator.workQueue
    resolveUntil:^{
      return [self bridgeForSimulator:simulator portName:portName];
    }]
    timeout:timeout waitingFor:@"Bridge Port %@ to exist", portName]
    onQueue:simulator.asyncQueue doOnResolved:^(NSProxy<SimulatorBridge> *bridge) {
      [simulator.logger logFormat:@"SimulatorBridge Proxy %@ for %@ is now ready", bridge, portName];
    }];
}

+ (FBFuture<NSProxy<SimulatorBridge> *> *)bridgeForSimulator:(FBSimulator *)simulator portName:(NSString *)portName
{
  return [[FBSimulatorBridge
    bridgePortForSimulator:simulator portName:portName]
    onQueue:simulator.workQueue fmap:^(NSNumber *bridgePort) {
      // Convert the bridge port to a remote object.
      NSPort *bridgeMachPort = [NSMachPort portWithMachPort:bridgePort.unsignedIntValue];
      NSConnection *bridgeConnection = [NSConnection connectionWithReceivePort:nil sendPort:bridgeMachPort];
      NSDistantObject *bridgeDistantObject = [bridgeConnection rootProxy];

      // Check that the Distant Object Responds to some known selector
      NSProxy<SimulatorBridge> *bridge = (NSProxy<SimulatorBridge> *) bridgeDistantObject;
      SEL knownSelector = @selector(setLocationScenarioWithPath:);
      if (![bridge respondsToSelector:knownSelector]) {
        return [[FBSimulatorError
          describeFormat:@"Distant Object '%@' for '%@' at isn't a SimulatorBridge as it doesn't respond to %@", portName, bridgeDistantObject, NSStringFromSelector(knownSelector)]
          failFuture];
      }

      return [FBFuture futureWithResult:bridge];
    }];
}

+ (FBFuture<NSNumber *> *)bridgePortForSimulator:(FBSimulator *)simulator portName:(NSString *)portName
{
  NSError *error = nil;
  mach_port_t bridgePort = [simulator.device lookup:portName error:&error];
  if (bridgePort == 0) {
    return [[[FBSimulatorError
      describeFormat:@"Could not lookup mach port for '%@'", portName]
      causedBy:error]
      failFuture];
  }
  return [FBFuture futureWithResult:@(bridgePort)];
}

- (instancetype)initWithBridge:(NSProxy<SimulatorBridge> *)bridge process:(FBProcess *)process workQueue:(dispatch_queue_t)workQueue asyncQueue:(dispatch_queue_t)asyncQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bridge = bridge;
  _process = process;
  _workQueue = workQueue;
  _asyncQueue = asyncQueue;

  return self;
}

#pragma mark Lifecycle

- (FBFuture<NSNull *> *)disconnect
{
  return [FBFuture
    onQueue:self.workQueue resolve:^ FBFuture<NSNull *> * {
      // Close the connection with the SimulatorBridge and nullify
      NSDistantObject *bridge = (NSDistantObject *) self.bridge;
      self.bridge = nil;
      if (!bridge) {
        return FBFuture.empty;
      }
      [[bridge connectionForProxy] invalidate];

      // Dispose of the process
      FBProcess *process = self.process;
      self.process = nil;
      if (!process) {
        return FBFuture.empty;
      }
      return [[process
        sendSignal:SIGTERM backingOffToKillWithTimeout:1 logger:nil]
        mapReplace:NSNull.null];
    }];
}

#pragma mark Interacting with the Simulator

- (FBFuture<NSNull *> *)enableAccessibility
{
  return [[self
    interactWithBridge]
    onQueue:self.workQueue fmap:^ FBFuture * _Nonnull (id<SimulatorBridge> bridge) {
      if ([bridge respondsToSelector:@selector(enableAccessibility)]) {
        [bridge performSelector:@selector(enableAccessibility)];
      }
      if (![bridge respondsToSelector:@selector(accessibilityEnabled)]) {
        return FBFuture.empty;
      }
      NSNumber *enabled = [bridge performSelector:@selector(accessibilityEnabled)];
      if (enabled.boolValue != YES) {
        return [[FBSimulatorError
          describeFormat:@"Could not enable accessibility for bridge '%@'", bridge]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityElements
{
  return [[[self
    interactWithBridge]
    onQueue:self.workQueue fmap:^(id<SimulatorBridge> bridge) {
      id elements = [bridge accessibilityElementsWithDisplayId:0];
      if (!elements) {
        return [[FBSimulatorError
          describeFormat:@"No Elements returned from bridge"]
          failFuture];
      }
      return [FBFuture futureWithResult:elements];
    }]
    onQueue:self.asyncQueue map:^(id elements) {
      return [FBSimulatorBridge jsonSerializableAccessibility:elements];
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityElementAtPoint:(NSPoint)point
{
  return [[[self
    interactWithBridge]
    onQueue:self.workQueue fmap:^(id<SimulatorBridge>bridge) {
      id element = [bridge accessibilityElementForPoint:point.x andY:point.y displayId:0];
      if (!element) {
        return [[FBSimulatorError
          describeFormat:@"No Elements at %f,%f returned from bridge", point.x, point.y]
          failFuture];
      }
      return [FBFuture futureWithResult:element];
    }]
    onQueue:self.asyncQueue map:^(id  element) {
      return [FBSimulatorBridge jsonSerializableElement:element];
    }];
}

- (FBFuture<NSNull *> *)setLocationWithLatitude:(double)latitude longitude:(double)longitude
{
  return [[self
    interactWithBridge]
    onQueue:self.workQueue fmap:^(id<SimulatorBridge>bridge) {
      [bridge setLocationWithLatitude:latitude andLongitude:longitude];
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)setHardwareKeyboardEnabled:(BOOL)enabled
{
  return [[self
    interactWithBridge]
    onQueue:self.workQueue fmap:^(id<SimulatorBridge> bridge) {
      [bridge setHardwareKeyboardEnabled:enabled keyboardType:0];
      return FBFuture.empty;
    }];
}

#pragma mark Private

- (FBFuture<id<SimulatorBridge>> *)interactWithBridge
{
  id<SimulatorBridge> bridge = self.bridge;
  if (!bridge) {
    return [[FBSimulatorError
      describeFormat:@"Cannot interact with bridge as it has been destroyed"]
      failFuture];
  }
  NSDistantObject *distantObject = (NSDistantObject *) bridge;
  if (!distantObject.connectionForProxy.isValid) {
    return [[FBSimulatorError
      describeFormat:@"Cannot interact with bridge as the connection is invalid"]
      failFuture];
  }

  return [FBFuture futureWithResult:bridge];
}

+ (NSArray<NSDictionary<NSString *, id> *> *)jsonSerializableAccessibility:(NSArray *)data
{
  NSMutableArray<NSDictionary<NSString *, id> *> *array = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *oldItem in data) {
    NSDictionary<NSString *, id> *item = [self jsonSerializableElement:oldItem];
    [array addObject:[item copy]];
  }
  return [array copy];
}

+ (NSDictionary<NSString *, id> *)jsonSerializableElement:(NSDictionary<NSString *, id> *)oldItem
{
  NSMutableDictionary<NSString *, id> *item = [NSMutableDictionary dictionary];
  for (NSString *key in oldItem.allKeys) {
    id value = oldItem[key];
    if ([key isEqualToString:KeyAXTraits]) {
      uint64_t bitmask = [(NSNumber *)value unsignedIntegerValue];
      item[KeyTraits] = AXExtractTraits(bitmask).allObjects;
      item[KeyType] = AXExtractTypeFromTraits(bitmask);
    }
    else if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
      item[key] = oldItem[key];
    } else if ([value isKindOfClass:NSValue.class]) {
      item[key] = NSStringFromRect([value rectValue]);
    }
  }
  return item;
}

#pragma mark NSObject

- (NSString *)description
{
  if (self.bridge) {
    return @"Simulator Bridge: Connected";
  }
  return @"Simulator Bridge: Disconnected";
}

@end

#pragma GCC diagnostic pop
