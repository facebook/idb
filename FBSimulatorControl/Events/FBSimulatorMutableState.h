/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorEventSink.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An Event Sink that stores received events as state.
 Then forwards these events to the provided sink, so that events are de-duplicated.
 */
@interface FBSimulatorMutableState : NSObject <FBSimulatorEventSink>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param launchdProcess the Simulator's `launchd_sim` process, if booted.
 @param containerApplication the Simulator's 'Container Application' process, if applicable.
 @param sink the sink to forward to.
 */
- (instancetype)initWithLaunchdProcess:(nullable FBProcessInfo *)launchdProcess containerApplication:(nullable FBProcessInfo *)containerApplication sink:(id<FBSimulatorEventSink>)sink;

#pragma mark Properties

/**
 The Simulator's `launchd_sim` process, if booted.
 */
@property (nonatomic, copy, nullable, readonly) FBProcessInfo *launchdProcess;

/**
 The Simulator's 'Container Application' process, if applicable.
 */
@property (nonatomic, copy, nullable, readonly) FBProcessInfo *containerApplication;

@end

NS_ASSUME_NONNULL_END
