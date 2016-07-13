/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlFrameworkLoader.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/NSUserDefaults-SimDefaults.h>

@implementation FBSimulatorControlFrameworkLoader

#pragma mark Framework Loading

static BOOL hasLoadedFrameworks = NO;

+ (void)loadPrivateFrameworksOrAbort
{
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  NSError *error = nil;
  BOOL success = [FBSimulatorControlFrameworkLoader loadPrivateFrameworks:logger.debug error:&error];
  if (success) {
    return;
  }
  [logger.error logFormat:@"Failed to private frameworks for FBSimulatorControl with error %@", error];
  abort();
}

+ (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (hasLoadedFrameworks) {
    return YES;
  }
  NSArray<FBWeakFramework *> *frameworks = @[
    FBWeakFramework.CoreSimulator,
    FBWeakFramework.SimulatorKit,
  ];
  BOOL result = [FBWeakFrameworkLoader loadPrivateFrameworks:frameworks logger:logger error:error];
  if (result) {
    // Set CoreSimulator Logging since it is now loaded.
    [self setCoreSimulatorLoggingEnabled:FBControlCoreGlobalConfiguration.debugLoggingEnabled];
    hasLoadedFrameworks = YES;
  }
  return result;
}

#pragma mark Private Methods

+ (void)setCoreSimulatorLoggingEnabled:(BOOL)enabled
{
  if (![NSUserDefaults instancesRespondToSelector:@selector(simulatorDefaults)]) {
    return;
  }
  NSUserDefaults *simulatorDefaults = [NSUserDefaults simulatorDefaults];
  [simulatorDefaults setBool:enabled forKey:@"DebugLogging"];
}

@end
