/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulator.h>

@class FBSimulatorControlConfiguration;

@interface FBSimulator ()

@property (nonatomic, strong, readwrite) SimDevice *device;
@property (nonatomic, weak, readwrite) FBSimulatorPool *pool;
@property (nonatomic, assign, readwrite) NSInteger processIdentifier;

+ (instancetype)inflateFromSimDevice:(SimDevice *)simDevice configuration:(FBSimulatorControlConfiguration *)configuration;

@end

@interface FBManagedSimulator ()

@property (nonatomic, assign, readwrite) NSInteger bucketID;
@property (nonatomic, assign, readwrite) NSInteger offset;

@end