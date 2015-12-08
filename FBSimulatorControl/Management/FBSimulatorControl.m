/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControl+Class.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import <DVTFoundation/DVTPlatform.h>

#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorApplicationSpecifier.h>
#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorSession.h>
#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorSessionConfig.h>

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl+Class.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSession+Convenience.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorSessionState.h"

@implementation FBSimulatorControl

#pragma mark - Initializers

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  [FBSimulatorControl doGlobalPreconditions];
  return [[FBSimulatorControl alloc] initWithConfiguration:configuration];
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulatorPool = [FBSimulatorPool poolWithConfiguration:configuration];
  return self;
}

#pragma mark - Public Methods

- (FBSimulatorSession *)createSessionForSimulatorConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration error:(NSError **)error;
{
  NSParameterAssert(simulatorConfiguration);

  NSError *innerError = nil;
  FBSimulator *simulator = [self.simulatorPool
    allocateSimulatorWithConfiguration:simulatorConfiguration
    error:&innerError];

  if (!simulator) {
    return [FBSimulatorError failWithError:innerError description:@"Failed to allocate simulator" errorOut:error];
  }
  return [FBSimulatorSession sessionWithSimulator:simulator];
}

#pragma mark - Private Methods

+ (void)doGlobalPreconditions
{
  static BOOL hasRunOnce = NO;
  if (!hasRunOnce) {
    return;
  }

  NSError *innerError = nil;
  NSAssert([DVTPlatform loadAllPlatformsReturningError:&innerError], @"Failed to load platforms will error %@", innerError);
}

@end
