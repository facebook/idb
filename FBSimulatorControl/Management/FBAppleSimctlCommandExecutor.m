/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAppleSimctlCommandExecutor.h"

#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulator.h"
#import "FBSimulatorSet.h"

@interface FBAppleSimctlCommandExecutor ()

@property (nonatomic, copy, readonly) NSString *deviceSetPath;
@property (nonatomic, copy, readonly) NSString *deviceUUID;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBAppleSimctlCommandExecutor

#pragma mark Initializers

+ (instancetype)executorForSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithDeviceSetPath:simulator.set.deviceSet.setPath deviceUUID:simulator.udid logger:[simulator.logger withName:@"simctl"]];
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
  NSArray<NSString *> *baseArguments = @[
    @"simctl",
    @"--set",
    self.deviceSetPath,
    command,
    self.deviceUUID,
  ];

  return [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/xcrun"
    arguments:[baseArguments arrayByAddingObjectsFromArray:arguments]]
    withStdOutToLogger:self.logger]
    withStdErrToLogger:self.logger]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@(0)]];
}

@end
