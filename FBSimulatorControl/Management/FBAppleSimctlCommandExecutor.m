/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAppleSimctlCommandExecutor.h"

#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulator.h"
#import "FBSimulatorSet.h"

@interface FBAppleSimctlCommandExecutor ()

@property (nonatomic, copy, readonly) NSString *deviceSetPath;
@property (nonatomic, copy, nullable, readonly) NSString *deviceUUID;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBAppleSimctlCommandExecutor

#pragma mark Initializers

+ (instancetype)executorForSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithDeviceSetPath:simulator.set.deviceSet.setPath deviceUUID:simulator.udid logger:[simulator.logger withName:@"simctl"]];
}

+ (instancetype)executorForDeviceSet:(FBSimulatorSet *)set
{
  return [[self alloc] initWithDeviceSetPath:set.deviceSet.setPath deviceUUID:nil logger:set.logger];
}

- (instancetype)initWithDeviceSetPath:(NSString *)deviceSetPath deviceUUID:(NSString *)deviceUUID logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceSetPath = deviceSetPath;
  _deviceUUID = deviceUUID;
  _logger = logger;
  _queue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.fbsimctl", DISPATCH_QUEUE_SERIAL);

  return self;
}

#pragma mark Public Methods

- (FBTaskBuilder<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *)taskBuilderWithCommand:(NSString *)command arguments:(NSArray<NSString *> *)arguments
{
  NSMutableArray<NSString *> *derived = [NSMutableArray arrayWithArray:@[
    @"simctl",
    @"--set",
    self.deviceSetPath,
    command,
  ]];
  if (self.deviceUUID) {
    [derived addObject:self.deviceUUID];
  }
  [derived addObjectsFromArray:arguments];

  return [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/xcrun"
    arguments:derived]
    withStdOutToLogger:self.logger]
    withStdErrToLogger:self.logger]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@(0)]];
}

@end
