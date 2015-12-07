/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulator.h>

@class FBProcessQuery;

@interface FBSimulator ()

@property (nonatomic, strong, readwrite) FBSimulatorLaunchInfo *launchInfo;
@property (nonatomic, strong, readwrite) SimDevice *device;
@property (nonatomic, weak, readwrite) FBSimulatorSession *session;
@property (nonatomic, copy, readwrite) FBSimulatorConfiguration *configuration;

@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;

+ (instancetype)fromSimDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration pool:(FBSimulatorPool *)pool query:(FBProcessQuery *)query;

- (void)wasLaunchedWithProcessIdentifier:(pid_t)processIdentifier;
- (void)wasTerminated;

@end
