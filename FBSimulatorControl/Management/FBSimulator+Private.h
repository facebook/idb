/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBSimulatorControl/FBSimulator.h>

@protocol FBControlCoreLogger;
@protocol FBEventReporter;

@interface FBSimulator ()

@property (nonnull, nonatomic, readwrite, copy) FBSimulatorConfiguration *configuration;
@property (nonnull, nonatomic, readonly, strong) id forwarder;

+ (nonnull instancetype)fromSimDevice:(nonnull SimDevice *)device configuration:(nullable FBSimulatorConfiguration *)configuration set:(nonnull FBSimulatorSet *)set;
- (nonnull instancetype)initWithDevice:(nonnull SimDevice *)device configuration:(nonnull FBSimulatorConfiguration *)configuration set:(nullable FBSimulatorSet *)set auxillaryDirectory:(nonnull NSString *)auxillaryDirectory logger:(nonnull id<FBControlCoreLogger>)logger reporter:(nonnull id<FBEventReporter>)reporter;
- (nonnull instancetype)initWithDevice:(nonnull id)device logger:(nonnull id<FBControlCoreLogger>)logger reporter:(nonnull id<FBEventReporter>)reporter;
@end
