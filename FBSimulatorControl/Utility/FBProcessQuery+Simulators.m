/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessQuery+Simulators.h"

#import "FBProcessInfo.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlStaticConfiguration.h"

@implementation FBProcessQuery (Simulators)

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

+ (NSPredicate *)simulatorProcessesMatchingSimulators:(NSArray *)simulators
{
  return [self simulatorProcessesMatchingUDIDs:[simulators valueForKey:@"udid"]];
}

+ (NSPredicate *)simulatorProcessesMatchingUDIDs:(NSArray *)udids
{
  NSSet *udidSet = [NSSet setWithArray:udids];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> process, NSDictionary *_) {
    NSSet *argumentSet = [NSSet setWithArray:process.arguments];
    return [udidSet intersectsSet:argumentSet];
  }];
}

+ (NSPredicate *)coreSimulatorProcessesForCurrentXcode
{
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> processInfo, NSDictionary *_) {
    return [processInfo.launchPath rangeOfString:FBSimulatorControlStaticConfiguration.developerDirectory].location != NSNotFound;
  }];
}

@end
