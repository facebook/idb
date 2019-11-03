/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBSimulatorControl/FBSimulatorEventSink.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBCompositeSimulatorEventSink : NSObject <FBSimulatorEventSink>

/**
 A Composite Sink that will notify an array of sinks.

 @param sinks the sinks to call.
 */
+ (instancetype)withSinks:(NSArray<id<FBSimulatorEventSink>> *)sinks;

@end

NS_ASSUME_NONNULL_END
