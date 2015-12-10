/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessQuery+Simulators.h"

#import <CoreSimulator/SimDevice.h>

#import "FBProcessInfo.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlStaticConfiguration.h"

@implementation FBProcessQuery (Simulators)

#pragma mark Process Fetching

- (NSArray *)simulatorProcesses
{
  // All Simulator Versions from Xcode 5-7, have Simulator.app in their path:
  // iOS Simulator.app/Contents/MacOS/iOS Simulator
  // Simulator.app/Contents/MacOS/Simulator
  return [self processesWithLaunchPathSubstring:@"Simulator.app"];
}

- (NSArray *)coreSimulatorServiceProcesses
{
  return [self processesWithLaunchPathSubstring:@"Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService"];
}

- (NSArray *)launchdSimProcesses
{
  return [self processesWithProcessName:@"launchd_sim"];
}

- (id<FBProcessInfo>)simulatorApplicationProcessForSimDevice:(SimDevice *)simDevice
{
  return [[[self simulatorProcesses]
    filteredArrayUsingPredicate:[FBProcessQuery simulatorProcessesMatchingUDIDs:@[simDevice.UDID.UUIDString]]]
    firstObject];
}

- (id<FBProcessInfo>)launchdSimProcessForSimDevice:(SimDevice *)simDevice
{
  return [[[self launchdSimProcesses]
    filteredArrayUsingPredicate:[FBProcessQuery launchdSimProcessesMatchingUDIDs:@[simDevice.UDID.UUIDString]]]
    firstObject];
}

#pragma mark Predicates

+ (NSPredicate *)simulatorsProcessesLaunchedUnderConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  // If it's from a different Xcode version, the binary path will be different.
  NSString *simulatorBinaryPath = configuration.simulatorApplication.binary.path;
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> process, NSDictionary *_) {
    return [process.launchPath isEqualToString:simulatorBinaryPath];
  }];
}

+ (NSPredicate *)simulatorProcessesLaunchedBySimulatorControl
{
  // All Simulators launched by FBSimulatorControl have a magic string in their environment.
  // This is the safest way to know about other processes launched by FBSimulatorControl
  // since other processes could have launched with UDID arguments.
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> process, NSDictionary *_) {
    NSSet *argumentSet = [NSSet setWithArray:process.environment.allKeys];
    return [argumentSet containsObject:FBSimulatorControlSimulatorLaunchEnvironmentMagic];
  }];
}

+ (NSPredicate *)simulatorProcessesMatchingUDIDs:(NSArray *)udids
{
  NSSet *udidSet = [NSSet setWithArray:udids];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> process, NSDictionary *_) {
    NSSet *argumentSet = [NSSet setWithArray:process.arguments];
    return [udidSet intersectsSet:argumentSet];
  }];
}

+ (NSPredicate *)launchdSimProcessesMatchingUDIDs:(NSArray *)udids
{
  NSPredicate *processNamePredicate = [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> process, NSDictionary *_) {
    return [process.launchPath rangeOfString:@"launchd_sim"].location != NSNotFound;
  }];

  NSMutableArray *udidPredicates = [NSMutableArray array];
  for (NSString *udid in udids) {
    NSPredicate *udidPredicate = [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> process, NSDictionary *_) {
      NSString *udidContainingString = process.environment[@"XPC_SIMULATOR_LAUNCHD_NAME"];
      return [udidContainingString rangeOfString:udid].location != NSNotFound;
    }];
    [udidPredicates addObject:udidPredicate];
  }

  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    processNamePredicate,
    [NSCompoundPredicate orPredicateWithSubpredicates:udidPredicates]
  ]];
}

+ (NSPredicate *)coreSimulatorProcessesForCurrentXcode
{
  return [self processesWithLaunchPath:FBSimulatorControlStaticConfiguration.developerDirectory];
}

+ (NSPredicate *)processesWithLaunchPath:(NSString *)launchPath
{
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> processInfo, NSDictionary *_) {
    return [processInfo.launchPath isEqualToString:launchPath];
  }];
}

@end
