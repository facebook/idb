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

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorControlFrameworkLoader.h"

@implementation FBSimulatorControl

#pragma mark Initializers

+ (void)initialize
{
  [FBSimulatorControlFrameworkLoader loadPrivateFrameworksOrAbort];
}

+ (nullable instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error
{
  return [self withConfiguration:configuration logger:FBControlCoreGlobalConfiguration.defaultLogger error:error];
}

+ (nullable instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  return [[FBSimulatorControl alloc] initWithConfiguration:configuration logger:logger error:error];
}

- (nullable instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
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

@end
