/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControl+PrincipalClass.h"

#import <Cocoa/Cocoa.h>

#import <CoreSimulator/NSUserDefaults-SimDefaults.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import <FBControlCore/FBControlCore.h>
#import <FBControlCore/FBWeakFramework+ApplePrivateFrameworks.h>

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSet.h"

@implementation FBSimulatorControl

#pragma mark Initializers

+ (void)initialize
{
  [FBSimulatorControl loadPrivateFrameworksOrAbort];
}

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error
{
  return [self withConfiguration:configuration logger:FBControlCoreGlobalConfiguration.defaultLogger error:error];
}

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  return [[FBSimulatorControl alloc] initWithConfiguration:configuration logger:logger error:error];
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = [FBSimulatorSet setWithConfiguration:configuration control:self logger:logger error:error];
  if (!_set) {
    return nil;
  }
  _configuration = configuration;
  _pool = [FBSimulatorPool poolWithSet:_set logger:logger];

  return self;
}

#pragma mark Framework Loading

+ (void)loadPrivateFrameworksOrAbort
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
    NSError *error = nil;
    BOOL success = [FBSimulatorControl loadPrivateFrameworks:logger.debug error:&error];
    if (success) {
      return;
    }
    [logger.error logFormat:@"Failed to private frameworks for FBSimulatorControl with error %@", error];
    abort();
  });
}

+ (BOOL)loadPrivateFrameworks:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSArray<FBWeakFramework *> *frameworks = @[
    [FBWeakFramework CoreSimulator],
    [FBWeakFramework SimulatorKit],
  ];
  BOOL result = [FBWeakFrameworkLoader loadPrivateFrameworks:frameworks logger:logger error:error];
  // Set CoreSimulator Logging since it is now loaded.
  [self setCoreSimulatorLoggingEnabled:FBControlCoreGlobalConfiguration.debugLoggingEnabled];
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
