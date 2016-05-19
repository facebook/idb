/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessFetcher+Simulators.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControlConfiguration.h"

NSString *const FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID = @"FBSIMULATORCONTROL_SIM_UDID";

@implementation FBProcessFetcher (Simulators)

#pragma mark Process Fetching

- (NSArray<FBProcessInfo *> *)simulatorProcesses
{
  // All Simulator Versions from Xcode 5-7, have Simulator.app in their path:
  // iOS Simulator.app/Contents/MacOS/iOS Simulator
  // Simulator.app/Contents/MacOS/Simulator
  return [self processesWithLaunchPathSubstring:@"Simulator.app"];
}

- (NSArray<FBProcessInfo *> *)coreSimulatorServiceProcesses
{
  return [self processesWithLaunchPathSubstring:@"Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService"];
}

- (NSArray<FBProcessInfo *> *)launchdSimProcesses
{
  return [self processesWithProcessName:@"launchd_sim"];
}

- (FBProcessInfo *)simulatorApplicationProcessForSimDevice:(SimDevice *)simDevice
{
  return [[[self simulatorProcesses]
    filteredArrayUsingPredicate:[FBProcessFetcher simulatorProcessesMatchingUDIDs:@[simDevice.UDID.UUIDString]]]
    firstObject];
}

- (FBProcessInfo *)simulatorApplicationProcessForSimDevice:(SimDevice *)simDevice timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilExists:^{
    return [self simulatorApplicationProcessForSimDevice:simDevice];
  }];
}

- (FBProcessInfo *)launchdSimProcessForSimDevice:(SimDevice *)simDevice
{
  return [[[self launchdSimProcesses]
    filteredArrayUsingPredicate:[FBProcessFetcher launchdSimProcessesMatchingUDIDs:@[simDevice.UDID.UUIDString]]]
    firstObject];
}

#pragma mark Predicates

+ (NSPredicate *)simulatorProcessesWithCorrectLaunchPath
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    return [process.launchPath isEqualToString:FBSimulatorApplication.xcodeSimulator.binary.path];
  }];
}

+ (NSPredicate *)simulatorsProcessesLaunchedUnderConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  NSString *deviceSetPath = configuration.deviceSetPath;
  NSPredicate *argumentsPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    NSSet *arguments = [NSSet setWithArray:process.arguments];
    return [arguments containsObject:deviceSetPath];
  }];

  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    self.simulatorProcessesWithCorrectLaunchPath,
    argumentsPredicate
  ]];
}

+ (NSPredicate *)simulatorProcessesLaunchedBySimulatorControl
{
  // All Simulators launched by FBSimulatorControl have a magic string in their environment.
  // This is the safest way to know about other processes launched by FBSimulatorControl
  // since other processes could have launched with UDID arguments.
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    NSSet *argumentSet = [NSSet setWithArray:process.environment.allKeys];
    return [argumentSet containsObject:FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID];
  }];
}

+ (NSPredicate *)simulatorProcessesMatchingUDIDs:(NSArray<NSString *> *)udids
{
  NSSet<NSString *> *udidSet = [NSSet setWithArray:udids];
  NSString *defaultsUDID = FBProcessFetcher.simulatorApplicationPreferences[@"CurrentDeviceUDID"];
  BOOL defaultsIntersection = [udidSet containsObject:defaultsUDID];

  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    // When the UDID environment marker is present we can use it alone to determine which UDID
    // corresponds to a running Simulator.app process.
    NSString *udid = process.environment[FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID];
    if (udid) {
      return [udidSet containsObject:udid];
    }

    // Otherwise we should use the 'cached' value from the defaults of 'com.apple.iphonesimulator.plist'
    return defaultsIntersection;
  }];
}

+ (NSPredicate *)launchdSimProcessesMatchingUDIDs:(NSArray<NSString *> *)udids
{
  NSPredicate *processNamePredicate = [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    return [process.launchPath rangeOfString:@"launchd_sim"].location != NSNotFound;
  }];

  NSMutableArray *udidPredicates = [NSMutableArray array];
  for (NSString *udid in udids) {
    NSPredicate *udidPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
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
  return [self processesWithLaunchPath:FBControlCoreGlobalConfiguration.developerDirectory];
}

+ (NSPredicate *)processesWithLaunchPath:(NSString *)launchPath
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *processInfo, NSDictionary *_) {
    return [processInfo.launchPath isEqualToString:launchPath];
  }];
}

+ (NSPredicate *)processesForBinary:(FBSimulatorBinary *)binary
{
  NSString *endPath = binary.path.lastPathComponent;
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *processInfo, NSDictionary *_) {
    return [processInfo.launchPath.lastPathComponent isEqualToString:endPath];
  }];
}

#pragma mark Private

+ (NSDictionary *)simulatorApplicationPreferences
{
  NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.apple.iphonesimulator.plist"];
  return [NSDictionary dictionaryWithContentsOfFile:path];
}

@end
