/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulator.h>

@class FBSimulatorConfiguration;
@class FBSimulatorControlConfiguration;

@interface FBSimulator ()

@property (nonatomic, strong, readwrite) SimDevice *device;
@property (nonatomic, weak, readwrite) FBSimulatorPool *pool;
@property (nonatomic, assign, readwrite) NSInteger processIdentifier;
@property (nonatomic, copy, readwrite) FBSimulatorConfiguration *configuration;

+ (instancetype)inflateFromSimDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration pool:(FBSimulatorPool *)pool;

@end
