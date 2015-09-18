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

#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorPool.h"
#import "NSRunLoop+SimulatorControlAdditions.h"
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

NSTimeInterval const FBSimulatorDefaultTimeout = 20;

@implementation FBSimulator

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processIdentifier = -1;
  return self;
}

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

- (BOOL)isAllocated
{
  NSParameterAssert(self.pool);
  return [self.pool.allocatedSimulators containsObject:self];
}

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

- (BOOL)freeFromPoolWithError:(NSError **)error
{
  NSParameterAssert(self.pool);
  NSParameterAssert(self.isAllocated);
  return [self.pool freeSimulator:self error:error];
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

#pragma mark NSObject

- (BOOL)isEqual:(FBSimulator *)device
{
  if (![device isKindOfClass:self.class]) {
    return NO;
  }
  return [self.device isEqual:device.device] &&
         self.bucketID == device.bucketID &&
         self.offset == device.offset;
}

- (NSUInteger)hash
{
  return self.device.hash | self.bucketID >> 1 | self.offset >> 2;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Name %@ | UUID %@ | State %@ | Bucket %ld | Offset %ld",
    self.name,
    self.udid,
    self.device.stateString,
    self.bucketID,
    self.offset
  ];
}

@end
