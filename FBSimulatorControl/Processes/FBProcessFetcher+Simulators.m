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

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"

NSString *const FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID = @"FBSIMULATORCONTROL_SIM_UDID";

@implementation FBProcessFetcher (Simulators)

#pragma mark - Process Fetching

#pragma mark The Container 'Simulator.app'

- (NSArray<FBProcessInfo *> *)simulatorApplicationProcesses
{
  // All Simulator Versions from Xcode 5-7, have Simulator.app in their path:
  // iOS Simulator.app/Contents/MacOS/iOS Simulator
  // Simulator.app/Contents/MacOS/Simulator
  return [self processesWithLaunchPathSubstring:@"Simulator.app"];
}

- (NSDictionary<NSString *, FBProcessInfo *> *)simulatorApplicationProcessesByUDIDs:(NSArray<NSString *> *)udids unclaimed:(NSArray<FBProcessInfo *> *_Nullable * _Nullable)unclaimedOut
{
  NSMutableDictionary<NSString *, FBProcessInfo *> *dictionary = [NSMutableDictionary dictionary];
  NSMutableArray<FBProcessInfo *> *unclaimed = unclaimedOut ? [NSMutableArray array] : nil;
  NSSet<NSString *> *fetchSet = [NSSet setWithArray:udids];

  for (FBProcessInfo *process in self.simulatorApplicationProcesses) {
    NSString *udid = [FBProcessFetcher udidForSimulatorApplicationProcess:process];
    if (!udid) {
      [unclaimed addObject:process];
    }
    if ([fetchSet containsObject:udid]) {
      dictionary[udid] = process;
    }
  }
  if (unclaimedOut) {
    *unclaimedOut = [unclaimed copy];
  }

  return [dictionary copy];
}

- (nullable FBProcessInfo *)simulatorApplicationProcessForSimDevice:(SimDevice *)simDevice
{
  return [self simulatorApplicationProcessesByUDIDs:@[simDevice.UDID.UUIDString] unclaimed:nil][simDevice.UDID.UUIDString];
}

- (nullable FBProcessInfo *)simulatorApplicationProcessForSimDevice:(SimDevice *)simDevice timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilExists:^{
    return [self simulatorApplicationProcessForSimDevice:simDevice];
  }];
}

#pragma mark The Simulator's launchd_sim

- (NSArray<FBProcessInfo *> *)launchdProcesses
{
  return [self processesWithProcessName:@"launchd_sim"];
}

- (NSDictionary<NSString *, FBProcessInfo *> *)launchdProcessesByUDIDs:(NSArray<NSString *> *)udids
{
  NSMutableDictionary<NSString *, FBProcessInfo *> *dictionary = [NSMutableDictionary dictionary];
  NSSet<NSString *> *fetchSet = [NSSet setWithArray:udids];

  for (FBProcessInfo *process in self.launchdProcesses) {
    NSString *udid = [FBProcessFetcher udidForLaunchdSim:process];
    if (!udid || ![fetchSet containsObject:udid]) {
      continue;
    }
    dictionary[udid] = process;
  }
  return [dictionary copy];
}

- (FBProcessInfo *)launchdProcessForSimDevice:(SimDevice *)simDevice
{
  return [self launchdProcessesByUDIDs:@[simDevice.UDID.UUIDString]][simDevice.UDID.UUIDString];
}

#pragma mark CoreSimulatorService

- (NSArray<FBProcessInfo *> *)coreSimulatorServiceProcesses
{
  return [self processesWithLaunchPathSubstring:@"Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService"];
}

#pragma mark Predicates

+ (NSPredicate *)simulatorProcessesWithCorrectLaunchPath
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    return [process.launchPath isEqualToString:FBApplicationDescriptor .xcodeSimulator.binary.path];
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

+ (NSPredicate *)simulatorApplicationProcessesLaunchedBySimulatorControl
{
  // All Simulators launched by FBSimulatorControl have a magic string in their environment.
  // This is the safest way to know about other processes launched by FBSimulatorControl
  // since other processes could have launched with UDID arguments.
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    NSSet *argumentSet = [NSSet setWithArray:process.environment.allKeys];
    return [argumentSet containsObject:FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID];
  }];
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

+ (NSPredicate *)processesForBinary:(FBBinaryDescriptor *)binary
{
  NSString *endPath = binary.path.lastPathComponent;
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *processInfo, NSDictionary *_) {
    return [processInfo.launchPath.lastPathComponent isEqualToString:endPath];
  }];
}

#pragma mark Private

+ (nullable NSString *)udidForLaunchdSim:(FBProcessInfo *)process
{
  if ([process.launchPath rangeOfString:@"launchd_sim"].location == NSNotFound) {
    return nil;
  }
  NSString *udidContainingString = process.environment[@"XPC_SIMULATOR_LAUNCHD_NAME"];
  NSCharacterSet *characterSet = self.launchdSimEnvironmentVariableUDIDSplitCharacterSet;
  NSMutableSet<NSString *> *components = [NSMutableSet setWithArray:[udidContainingString componentsSeparatedByCharactersInSet:characterSet]];
  [components minusSet:self.launchdSimEnvironmentSubtractableComponents];
  if (components.count != 1) {
    return nil;
  }
  return [components anyObject];
}

+ (nullable NSString *)udidForSimulatorApplicationProcess:(FBProcessInfo *)process
{
  return process.environment[FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID];
}

+ (NSCharacterSet *)launchdSimEnvironmentVariableUDIDSplitCharacterSet
{
  static dispatch_once_t onceToken;
  static NSCharacterSet *characterSet;
  dispatch_once(&onceToken, ^{
    characterSet = [NSCharacterSet characterSetWithCharactersInString:@"."];
  });
  return characterSet;
}

+ (NSSet<NSString *> *)launchdSimEnvironmentSubtractableComponents
{
  static dispatch_once_t onceToken;
  static NSSet<NSString *> *components;
  dispatch_once(&onceToken, ^{
    components = [NSSet setWithArray:@[
      @"com",
      @"apple",
      @"CoreSimulator",
      @"SimDevice",
      @"launchd_sim",
    ]];
  });
  return components;
}

@end
