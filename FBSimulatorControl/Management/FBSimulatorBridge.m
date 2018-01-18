/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBridge.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>
#import <SimulatorBridge/SimulatorBridge.h>

#import "FBSimulator.h"
#import "FBApplicationBundle+Simulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorAgentOperation.h"

@interface FBSimulatorBridge ()

@property (nonatomic, strong, nullable, readwrite) SimulatorBridge *bridge;
@property (nonatomic, strong, nullable, readwrite) FBSimulatorAgentOperation *operation;

@end

@implementation FBSimulatorBridge

#pragma mark Initializers

+ (nullable FBBinaryDescriptor *)simulatorBridgeBinaryWithError:(NSError **)error
{
  FBApplicationBundle *simulatorApp = [FBApplicationBundle xcodeSimulator];
  NSString *path = [simulatorApp.path stringByAppendingPathComponent:@"Contents/Resources/Platforms/iphoneos/usr/libexec/SimulatorBridge"];
  return [FBBinaryDescriptor binaryWithPath:path error:error];
}

+ (FBFuture<FBSimulatorBridge *> *)bridgeForSimulator:(FBSimulator *)simulator
{
  // Connect to the expected-to-be-running CoreSimulatorBridge running inside the Simulator.
  // This mimics the behaviour of Simulator.app, which just looks up the service then connects to the distant object over a Remote Object connection.
  return [[self
    bridgeAndOperationForSimulator:simulator]
    onQueue:simulator.workQueue map:^(NSArray<id> *tuple) {
      NSCParameterAssert(tuple.count >= 1);
      SimulatorBridge *bridge = tuple[0];
      FBSimulatorAgentOperation *operation = (tuple.count == 2) ? tuple[1] : nil;
      return [[FBSimulatorBridge alloc] initWithBridge:bridge operation:operation];
    }];
}

+ (FBFuture<NSArray<id> *> *)bridgeAndOperationForSimulator:(FBSimulator *)simulator;
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
      return [FBFuture futureWithFutures:@[future]];
    }];
}

static NSString *const SimulatorBridgePortSuffix = @"FBSimulatorControl";

+ (NSString *)portNameForSimulator:(FBSimulator *)simulator
{
  NSString *portName = @"com.apple.iphonesimulator.bridge";
  if (!FBXcodeConfiguration.isXcode9OrGreater) {
    return portName;
  }
  return [portName stringByAppendingFormat:@".%@", SimulatorBridgePortSuffix];
}

+ (FBFuture<FBSimulatorAgentOperation *> *)bridgeOperationForSimulator:(FBSimulator *)simulator portName:(NSString *)portName
{
  NSError *error = nil;
  FBBinaryDescriptor *bridgeBinary = [self simulatorBridgeBinaryWithError:&error];
  if (!bridgeBinary) {
    return [FBFuture futureWithError:error];
  }

  FBAgentLaunchConfiguration *config = [FBAgentLaunchConfiguration
    configurationWithBinary:bridgeBinary
    arguments:@[portName]
    environment:@{}
    output:FBProcessOutputConfiguration.outputToDevNull];

  return [simulator launchAgent:config];
}

+ (FBFuture<SimulatorBridge *> *)bridgeForSimulator:(FBSimulator *)simulator portName:(NSString *)portName timeout:(NSTimeInterval)timeout
{
  return [[FBFuture
    onQueue:simulator.workQueue
    resolveUntil:^{
      return [self bridgeForSimulator:simulator portName:portName];
    }]
    timeout:timeout waitingFor:@"Bridge Port to exist"];
}

+ (FBFuture<SimulatorBridge *> *)bridgeForSimulator:(FBSimulator *)simulator portName:(NSString *)portName
{
  return [[FBSimulatorBridge
    bridgePortForSimulator:simulator portName:portName]
    onQueue:simulator.workQueue fmap:^(NSNumber *bridgePort) {
      // Convert the bridge port to a remote object.
      NSPort *bridgeMachPort = [NSMachPort portWithMachPort:bridgePort.unsignedIntValue];
      NSConnection *bridgeConnection = [NSConnection connectionWithReceivePort:nil sendPort:bridgeMachPort];
      NSDistantObject *bridgeDistantObject = [bridgeConnection rootProxy];

      // Check that the Distant Object Responds to some known selector
      if (![bridgeDistantObject respondsToSelector:@selector(setLocationScenarioWithPath:)]) {
        return [[FBSimulatorError
          describeFormat:@"Distant Object '%@' for '%@' at isn't a SimulatorBridge", portName, bridgeDistantObject]
          failFuture];
      }

      // Set the Bridge to a good state.
      SimulatorBridge *bridge = (SimulatorBridge *) bridgeDistantObject;
      [bridge enableAccessibility];
      if (![bridge accessibilityEnabled]) {
        return [[FBSimulatorError
          describeFormat:@"Could not enable accessibility for bridge '%@'", bridge]
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

- (instancetype)initWithBridge:(SimulatorBridge *)bridge operation:(FBSimulatorAgentOperation *)operation
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bridge = bridge;
  _operation = operation;

  return self;
}

#pragma mark Lifecycle

- (void)disconnect
{
  if (!self.bridge) {
    return;
  }

  // Close the connection with the SimulatorBridge and nullify
  NSDistantObject *distantObject = (NSDistantObject *) self.bridge;
  self.bridge = nil;
  [[distantObject connectionForProxy] invalidate];

  // Dispose of the operation
  [self.operation.completed cancel];
  self.operation = nil;
}

#pragma mark Interacting with the Simulator

- (NSArray<NSDictionary<NSString *, id> *> *)accessibilityElements
{
  id elements = [self.bridge accessibilityElementsWithDisplayId:0];
  return [FBSimulatorBridge jsonSerializableAccessibility:elements] ?: @[];
}

- (void)setLocationWithLatitude:(double)latitude longitude:(double)longitude
{
  [self.bridge setLocationWithLatitude:latitude andLongitude:longitude];
}

- (pid_t)launch:(FBApplicationLaunchConfiguration *)configuration stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath error:(NSError **)error
{
  NSDictionary<NSString *, id> *result = [self.bridge
    bksLaunchApplicationWithBundleId:configuration.bundleID
    arguments:configuration.arguments
    environment:configuration.environment
    standardOutPipe:stdOutPath
    standardErrorPipe:stdErrPath
    options:@{}];

  if ([result[@"result"] integerValue] != 0) {
    [[FBSimulatorError describeFormat:@"Non-Zero result %@", result] fail:error];
    return -1;
  }

  pid_t processIdentifier = [result[@"pid"] intValue];
  if (processIdentifier <= 0) {
    [[FBSimulatorError describeFormat:@"No Pid Value in result %@", result] fail:error];
    return -1;
  }

  return processIdentifier;
}

#pragma mark Private

+ (NSArray<NSDictionary<NSString *, id> *> *)jsonSerializableAccessibility:(NSArray *)data
{
  NSMutableArray<NSDictionary<NSString *, id> *> *array = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *oldItem in data) {
    NSMutableDictionary<NSString *, id> *item = [NSMutableDictionary dictionary];
    for (NSString *key in oldItem.allKeys) {
      id value = oldItem[key];
      if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
        item[key] = oldItem[key];
      } else if ([value isKindOfClass:NSValue.class]) {
        item[key] = NSStringFromRect([value rectValue]);
      }
    }
    [array addObject:[item copy]];
  }
  return [array copy];
}

#pragma mark NSObject

- (NSString *)description
{
  if (self.bridge) {
    return @"Simulator Bridge: Connected";
  }
  return @"Simulator Bridge: Disconnected";
}

#pragma mark FBJSONSerialization

- (id)jsonSerializableRepresentation
{
  return @{
    @"connected" : (self.bridge ? @YES : @NO ),
  };
}

@end
