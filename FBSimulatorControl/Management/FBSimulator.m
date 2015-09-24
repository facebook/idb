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

#import "FBSimulatorConfiguration.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBTaskExecutor.h"
#import "FBSimulatorPool.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

NSTimeInterval const FBSimulatorDefaultTimeout = 20;

@implementation FBSimulator

@synthesize processIdentifier = _processIdentifier;

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

+ (instancetype)inflateFromSimDevice:(SimDevice *)device configuration:(FBSimulatorControlConfiguration *)configuration
{
  // Attempt to make a Managed Simulator, otherwise this must be an unmanaged one.
  FBSimulator *simulator = [FBManagedSimulator inflateFromSimDevice:device configuration:configuration];
  if (simulator) {
    return simulator;
  }

  // Create and return an unmanaged one.
  simulator = [FBSimulator new];
  simulator.device = device;
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

@end

@implementation FBManagedSimulator

@synthesize configuration = _configuration;

+ (instancetype)inflateFromSimDevice:(SimDevice *)device configuration:(FBSimulatorControlConfiguration *)configuration
{
  NSRegularExpression *regex = [FBManagedSimulator managedSimulatorPoolOffsetRegex:configuration];
  NSTextCheckingResult *result = [regex firstMatchInString:device.name options:0 range:NSMakeRange(0, device.name.length)];
  if (result.range.length == 0) {
    return nil;
  }

  NSInteger bucketID = [[device.name substringWithRange:[result rangeAtIndex:1]] integerValue];
  NSInteger offset = [[device.name substringWithRange:[result rangeAtIndex:2]] integerValue];

  FBManagedSimulator *simulator = [FBManagedSimulator new];
  simulator.device = device;
  simulator.bucketID = bucketID;
  simulator.offset = offset;
  return simulator;
}

#pragma mark Accessors

- (BOOL)isAllocated
{
  if (!self.pool) {
    return NO;
  }
  return [self.pool.allocatedSimulators containsObject:self];
}

- (void)setConfiguration:(FBSimulatorConfiguration *)configuration
{
  _configuration = configuration;
}

- (FBSimulatorConfiguration *)configuration
{
  return _configuration ?: [self inferredSimulatorConfiguration];
}

#pragma mark Interactions

- (BOOL)freeFromPoolWithError:(NSError **)error
{
  NSParameterAssert(self.pool);
  NSParameterAssert(self.isAllocated);
  return [self.pool freeSimulator:self error:error];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBManagedSimulator *)simulator
{
  return [super isEqual:simulator] &&
         self.bucketID == simulator.bucketID &&
         self.offset == simulator.offset;
}

- (NSUInteger)hash
{
  return [super hash] | self.bucketID >> 1 | self.offset >> 2;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"%@ | Bucket %ld | Offset %ld",
    [super description],
    self.bucketID,
    self.offset
  ];
}

#pragma mark Private

- (FBSimulatorConfiguration *)inferredSimulatorConfiguration
{
  return [[FBSimulatorConfiguration.defaultConfiguration withDeviceType:self.device.deviceType] withRuntime:self.device.runtime];
}

+ (NSRegularExpression *)managedSimulatorPoolOffsetRegex:(FBSimulatorControlConfiguration *)configuration
{
  static dispatch_once_t onceToken;
  static NSMutableDictionary *regexDictionary;
  dispatch_once(&onceToken, ^{
    regexDictionary = [NSMutableDictionary dictionary];
  });

  if (!regexDictionary[configuration]) {
    NSString *regexString = [NSString stringWithFormat:@"%@_(\\d+)_(\\d+)", configuration.namePrefix];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexString options:0 error:nil];
    NSAssert(regex, @"Regex '%@' for '%@' should compile", regexString, NSStringFromSelector(_cmd));
    regexDictionary[configuration] = regex;
    return regex;
  }

  return regexDictionary[configuration];
}

@end
