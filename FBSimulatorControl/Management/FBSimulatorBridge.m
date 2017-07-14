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
  FBApplicationDescriptor *simulatorApp = [FBApplicationDescriptor xcodeSimulator];
  NSString *path = [simulatorApp.path stringByAppendingPathComponent:@"Contents/Resources/Platforms/iphoneos/usr/libexec/SimulatorBridge"];
  return [FBBinaryDescriptor binaryWithPath:path error:error];
}

+ (nullable instancetype)bridgeForSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  // Connect to the expected-to-be-running CoreSimulatorBridge running inside the Simulator.
  // This mimics the behaviour of Simulator.app, which just looks up the service then connects to the distant object over a Remote Object connection.
  FBSimulatorAgentOperation *operation = nil;
  NSString *portName = [self portNameForSimulator:simulator operationOut:&operation error:error];
  if (!portName) {
    return nil;
  }
  // Get the Bridge
  SimulatorBridge *bridge = [self bridgeForSimulator:simulator portName:portName operation:operation error:error];
  if (!bridge) {
    return nil;
  }

  // Load Accessibility, return early if this fails
  [bridge enableAccessibility];
  if (![bridge accessibilityEnabled]) {
    return [[FBSimulatorError
      describeFormat:@"Could not enable accessibility for bridge '%@'", bridge]
      fail:error];
  }

  return [[FBSimulatorBridge alloc] initWithBridge:bridge operation:operation];
}

+ (nullable NSString *)portNameForSimulator:(FBSimulator *)simulator operationOut:(FBSimulatorAgentOperation **)operationOut error:(NSError **)error
{
  NSString *portName = @"com.apple.iphonesimulator.bridge";
  if (!FBControlCoreGlobalConfiguration.isXcode9OrGreater) {
    return portName;
  }
  FBBinaryDescriptor *bridgeBinary = [self simulatorBridgeBinaryWithError:error];
  if (!bridgeBinary) {
    return nil;
  }
  portName = [portName stringByAppendingFormat:@".%d", getpid()];
  FBAgentLaunchConfiguration *config = [FBAgentLaunchConfiguration
    configurationWithBinary:bridgeBinary
    arguments:@[portName]
    environment:@{}
    output:FBProcessOutputConfiguration.outputToDevNull];
  FBSimulatorAgentOperation *operation = [simulator launchAgent:config error:error];
  if (!operation) {
    return nil;
  }
  if (operationOut) {
    *operationOut = operation;
  }
  return portName;
}

+ (SimulatorBridge *)bridgeForSimulator:(FBSimulator *)simulator portName:(NSString *)portName operation:(FBSimulatorAgentOperation *)operation error:(NSError **)error
{
  __block NSError *innerError;
  __block mach_port_t bridgePort = [simulator.device lookup:portName error:&innerError];
  if (!bridgePort && operation) {
    [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^BOOL{
      bridgePort = [simulator.device lookup:portName error:&innerError];
      return bridgePort != 0;
    }];
  }
  if (bridgePort == 0) {
    return [[[FBSimulatorError
      describeFormat:@"Could not lookup mach port for '%@'", portName]
      inSimulator:simulator]
      fail:error];
  }
  NSPort *bridgeMachPort = [NSMachPort portWithMachPort:bridgePort];
  NSConnection *bridgeConnection = [NSConnection connectionWithReceivePort:nil sendPort:bridgeMachPort];
  NSDistantObject *bridgeDistantObject = [bridgeConnection rootProxy];

  if (![bridgeDistantObject respondsToSelector:@selector(setLocationScenarioWithPath:)]) {
    return [[FBSimulatorError
      describeFormat:@"Distant Object '%@' for '%@' at isn't a SimulatorBridge", portName, bridgeDistantObject]
      fail:error];
  }

  return (SimulatorBridge *) bridgeDistantObject;
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
  [self.operation terminate];
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
