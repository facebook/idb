/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBSimulatorControl/FBSimulator.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;
@protocol FBEventReporter;

@interface FBSimulator ()

@property (nonatomic, copy, readwrite) FBSimulatorConfiguration *configuration;
@property (nonatomic, strong, readonly) id forwarder;

+ (instancetype)fromSimDevice:(SimDevice *)device configuration:(nullable FBSimulatorConfiguration *)configuration set:(FBSimulatorSet *)set;
- (instancetype)initWithDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration set:(nullable FBSimulatorSet *)set auxillaryDirectory:(NSString *)auxillaryDirectory logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter;
- (instancetype)initWithDevice:(id)device logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter;
@end

NS_ASSUME_NONNULL_END
