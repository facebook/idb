/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBridge.h"

#import <CoreSimulator/SimDevice.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>
#import <SimulatorBridge/SimulatorBridge.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorBridge ()

@property (nonatomic, strong, readwrite) SimulatorBridge *bridge;

@end

@implementation FBSimulatorBridge

+ (nullable instancetype)bridgeForSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  // Connect to the expected-to-be-running CoreSimulatorBridge running inside the Simulator.
  // This mimics the behaviour of Simulator.app, which just looks up the service then connects to the distant object over a Remote Object connection.
  NSError *innerError = nil;
  mach_port_t bridgePort = [simulator.device lookup:@"com.apple.iphonesimulator.bridge" error:&innerError];
  if (bridgePort == 0) {
    return [[[FBSimulatorError
      describe:@"Could not lookup mach port for 'com.apple.iphonesimulator.bridge'"]
      inSimulator:simulator]
      fail:error];
  }
  NSPort *bridgeMachPort = [NSMachPort portWithMachPort:bridgePort];
  NSConnection *bridgeConnection = [NSConnection connectionWithReceivePort:nil sendPort:bridgeMachPort];
  NSDistantObject *bridgeDistantObject = [bridgeConnection rootProxy];

  if (![bridgeDistantObject respondsToSelector:@selector(setLocationScenarioWithPath:)]) {
    return [[FBSimulatorError
      describeFormat:@"Distant Object '%@' for 'com.apple.iphonesimulator.bridge' at isn't a SimulatorBridge", bridgeDistantObject]
      fail:error];
  }

  // Load Accessibility, return early if this fails
  SimulatorBridge *bridge = (SimulatorBridge *) bridgeDistantObject;
  [bridge enableAccessibility];
  if (![bridge accessibilityEnabled]) {
    return [[FBSimulatorError
      describeFormat:@"Could not enable accessibility for bridge '%@'", bridge]
      fail:error];
  }

  return [[FBSimulatorBridge alloc] initWithBridge:bridge];
}

- (instancetype)initWithBridge:(id)bridge
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bridge = bridge;

  return self;
}

- (void)disconnect
{
  if (!self.bridge) {
    return;
  }

  // Close the connection with the SimulatorBridge and nullify
  NSDistantObject *distantObject = (NSDistantObject *) self.bridge;
  self.bridge = nil;
  [[distantObject connectionForProxy] invalidate];
}

#pragma mark Interacting with the Simulator

- (void)setLocationWithLatitude:(double)latitude longitude:(double)longitude
{
  [self.bridge setLocationWithLatitude:latitude andLongitude:longitude];
}

- (BOOL)tapX:(double)x y:(double)y error:(NSError **)error
{
  NSDictionary *elementDictionary = [self.bridge accessibilityElementForPoint:x andY:y displayId:0];
  if (!elementDictionary) {
    return [[FBSimulatorError
      describeFormat:@"Could not find element at (%f, %f)", x, y]
      failBool:error];
  }
  if (![self.bridge performPressAction:elementDictionary]) {
    return [[FBSimulatorError
      describeFormat:@"Could not Press Element with description %@", elementDictionary]
      failBool:error];
  }
  return YES;
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

#pragma mark FBDebugDescribable

- (NSString *)description
{
  if (self.bridge) {
    return @"Simulator Bridge: Connected";
  }
  return @"Simulator Bridge: Disconnected";
}

- (NSString *)shortDescription
{
  return self.description;
}

- (NSString *)debugDescription
{
  return self.description;
}

#pragma mark FBJSONSerialization

- (id)jsonSerializableRepresentation
{
  return @{
    @"connected" : (self.bridge ? @YES : @NO ),
  };
}

@end
