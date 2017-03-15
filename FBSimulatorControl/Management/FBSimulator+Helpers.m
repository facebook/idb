/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulator+Helpers.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator+Private.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorSet.h"

#import <AppKit/AppKit.h>

@implementation FBSimulator (Helpers)

#pragma mark Properties

- (FBSimulatorLaunchCtl *)launchctl
{
  return [FBSimulatorLaunchCtl withSimulator:self];
}

- (NSString *)deviceSetPath
{
  return self.set.deviceSet.setPath;
}

- (NSArray<FBProcessInfo *> *)launchdSimSubprocesses
{
  FBProcessInfo *launchdSim = self.launchdProcess;
  if (!launchdSim) {
    return @[];
  }
  return [self.processFetcher.processFetcher subprocessesOf:launchdSim.processIdentifier];
}

#pragma mark Methods

+ (FBSimulatorState)simulatorStateFromStateString:(NSString *)stateString
{
  return FBSimulatorStateFromStateString(stateString);
}

+ (NSString *)stateStringFromSimulatorState:(FBSimulatorState)state
{
  return FBSimulatorStateStringFromState(state);
}

- (BOOL)waitOnState:(FBSimulatorState)state
{
  return [self waitOnState:state timeout:FBControlCoreGlobalConfiguration.regularTimeout];
}

- (BOOL)waitOnState:(FBSimulatorState)state timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    return self.state == state;
  }];
}

- (BOOL)waitOnState:(FBSimulatorState)state withError:(NSError **)error
{
  if (![self waitOnState:state]) {
    return [[[FBSimulatorError
      describeFormat:@"Simulator was not in expected %@ state, got %@", [FBSimulator stateStringFromSimulatorState:state], self.stateString]
      inSimulator:self]
      failBool:error];
  }
  return YES;
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

- (BOOL)eraseWithError:(NSError **)error
{
  return [self.set eraseSimulator:self error:error];
}

- (BOOL)focusWithError:(NSError **)error
{
  NSArray *apps = NSWorkspace.sharedWorkspace.runningApplications;
  NSPredicate *matchingPid = [NSPredicate predicateWithFormat:@"processIdentifier = %@", @(self.containerApplication.processIdentifier)];
  NSRunningApplication *app = [apps filteredArrayUsingPredicate:matchingPid].firstObject;
  if (!app) {
    return [[FBSimulatorError describeFormat:@"Simulator application for %@ is not running", self.udid] failBool:error];
  }

  return [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

+ (NSDictionary<NSString *, id> *)simulatorApplicationPreferences
{
  NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.apple.iphonesimulator.plist"];
  return [NSDictionary dictionaryWithContentsOfFile:path];
}

@end
