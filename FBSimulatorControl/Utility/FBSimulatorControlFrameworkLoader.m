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

+ (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (hasLoadedFrameworks) {
    return YES;
  }
  if (![super loadPrivateFrameworks:logger error:error]) {
    return NO;
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

+ (NSString *)loadingFrameworkName
{
  return @"FBSimulatorControl";
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
