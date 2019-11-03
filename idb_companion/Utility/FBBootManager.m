/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBootManager.h"

#import <FBControlCore/FBControlCoreLogger.h>
#import "FBiOSTargetProvider.h"
#import <FBSimulatorControl/FBSimulatorControl.h>

@interface FBBootManager ()

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBBootManager

#pragma mark Initializers

+ (instancetype)bootManagerForLogger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithLogger:logger];
}

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  self = [super init];

  if (!self) {
    return nil;
  }
  _logger = logger;
  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)boot:(NSString *)udid
{
  NSError *error = nil;
  id<FBiOSTarget> target = [FBiOSTargetProvider targetWithUDID:udid logger:_logger reporter:nil error:&error];
  if (target.targetType != FBiOSTargetTypeSimulator) {
    return [[FBControlCoreError describe:@"You can only boot simulators. please provide a UDID for a simulator"] failFuture];
  } else if (target.state == FBiOSTargetStateBooted) {
    return [[FBControlCoreError describe:@"Simulator is already booted"] failFuture];
  }
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  return [commands boot];
}

@end
