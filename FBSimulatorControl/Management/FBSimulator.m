/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulator.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorPool+Private.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLogs.h"
#import "FBSimulatorPool.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

NSTimeInterval const FBSimulatorDefaultTimeout = 20;

@implementation FBSimulator

@synthesize processIdentifier = _processIdentifier;
@synthesize configuration = _configuration;


#pragma mark Initializers

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processIdentifier = -1;
  return self;
}

+ (instancetype)inflateFromSimDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration pool:(FBSimulatorPool *)pool
{
  // Create and return an unmanaged one.
  FBSimulator *simulator = [FBSimulator new];
  simulator.device = device;
  simulator.pool = pool;
  simulator.configuration = configuration;
  return simulator;
}

#pragma mark Properties

- (NSString *)name
{
  return self.device.name;
}

- (NSString *)udid
{
  return self.device.UDID.UUIDString;
}

- (FBSimulatorState)state
{
  return self.device.state;
}

- (FBSimulatorApplication *)simulatorApplication
{
  return self.pool.configuration.simulatorApplication;
}

- (NSString *)dataDirectory
{
  return self.device.dataPath;
}

- (NSString *)launchdBootstrapPath
{
  NSString *expectedPath = [[self.pool.deviceSet.setPath
    stringByAppendingPathComponent:self.udid]
    stringByAppendingPathComponent:@"/data/var/run/launchd_bootstrap.plist"];

  if (![NSFileManager.defaultManager fileExistsAtPath:expectedPath]) {
    return nil;
  }
  return expectedPath;
}

- (NSInteger)launchdSimProcessIdentifier
{
  NSString *bootstrapPath = self.launchdBootstrapPath;
  if (!bootstrapPath) {
    return -1;
  }

  NSInteger processIdentifier = [[[[FBTaskExecutor.sharedInstance
    taskWithLaunchPath:@"/usr/bin/pgrep" arguments:@[@"-f", bootstrapPath]]
    startSynchronouslyWithTimeout:5]
    stdOut]
    integerValue];

  if (processIdentifier < 2) {
    return -1;
  }
  return processIdentifier;
}

- (NSInteger)processIdentifier
{
  return _processIdentifier > 1 ? _processIdentifier : [self inferredProcessIdentifier];
}

- (void)setProcessIdentifier:(NSInteger)processIdentifier
{
  _processIdentifier = processIdentifier;
}

- (FBSimulatorConfiguration *)configuration
{
  return _configuration ?: [self inferredSimulatorConfiguration];
}

- (void)setConfiguration:(FBSimulatorConfiguration *)configuration
{
  _configuration = configuration;
}

- (BOOL)isAllocated
{
  if (!self.pool) {
    return NO;
  }
  return [self.pool.allocatedSimulators containsObject:self];
}

- (FBSimulatorLogs *)logs
{
  return [FBSimulatorLogs withSimulator:self];
}

#pragma mark Helpers

+ (FBSimulatorState)simulatorStateFromStateString:(NSString *)stateString
{
  stateString = [stateString lowercaseString];
  if ([stateString isEqualToString:@"creating"]) {
    return FBSimulatorStateCreating;
  }
  if ([stateString isEqualToString:@"shutdown"]) {
    return FBSimulatorStateShutdown;
  }
  if ([stateString isEqualToString:@"booting"]) {
    return FBSimulatorStateBooting;
  }
  if ([stateString isEqualToString:@"booted"]) {
    return FBSimulatorStateBooted;
  }
  if ([stateString isEqualToString:@"creating"]) {
    return FBSimulatorStateCreating;
  }
  if ([stateString isEqualToString:@"shutting down"]) {
    return FBSimulatorStateCreating;
  }
  return FBSimulatorStateUnknown;
}

+ (NSString *)stateStringFromSimulatorState:(FBSimulatorState)state
{
  switch (state) {
    case FBSimulatorStateCreating:
      return @"Creating";
    case FBSimulatorStateShutdown:
      return @"Shutdown";
    case FBSimulatorStateBooting:
      return @"Booting";
    case FBSimulatorStateBooted:
      return @"Booted";
    case FBSimulatorStateShuttingDown:
      return @"Shutting Down";
    default:
      return @"Unknown";
  }
}

- (BOOL)waitOnState:(FBSimulatorState)state
{
  return [self waitOnState:state timeout:FBSimulatorDefaultTimeout];
}

- (BOOL)waitOnState:(FBSimulatorState)state timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    return self.state == state;
  }];
}

- (BOOL)freeFromPoolWithError:(NSError **)error
{
  if (!self.pool) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot free from pool as there is no pool associated" errorOut:error];
  }
  if (!self.isAllocated) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot free from pool as this Simulator has not been allocated" errorOut:error];
  }
  return [self.pool freeSimulator:self error:error];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.device.hash;
}

- (BOOL)isEqual:(FBSimulator *)simulator
{
  if (![simulator isKindOfClass:self.class]) {
    return NO;
  }
  return [self.device isEqual:simulator.device];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Name %@ | UUID %@ | State %@",
    self.name,
    self.udid,
    self.device.stateString
  ];
}

#pragma mark Private

- (NSInteger)inferredProcessIdentifier
{
  // It's possible to find Simulators that have been launched with 'CurrentDeviceUDID' but not otherwise.
  // Simulators launched via Xcode have some sort of token with an argument such as '-psn_0_2466394'.
  // Finding these Simulators is currently unimplemented.
  NSString *expectedArgument = [NSString stringWithFormat:@"CurrentDeviceUDID %@", self.udid];
  NSInteger processIdentifier = [[[[FBTaskExecutor.sharedInstance
    taskWithLaunchPath:@"/usr/bin/pgrep" arguments:@[@"-f", expectedArgument]]
    startSynchronouslyWithTimeout:5]
    stdOut]
    integerValue];

  if (processIdentifier < 1) {
    return -1;
  }
  return processIdentifier;
}

- (FBSimulatorConfiguration *)inferredSimulatorConfiguration
{
  return [[FBSimulatorConfiguration.defaultConfiguration withDeviceType:self.device.deviceType] withRuntime:self.device.runtime];
}

@end
