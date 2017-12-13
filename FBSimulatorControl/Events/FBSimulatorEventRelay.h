/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorEventSink.h>

@class FBSimulatorProcessFetcher;

NS_ASSUME_NONNULL_BEGIN

/**
 Automatically subscribes to event sources that create Simulator Events passively.
 The results of these event sources are translated into events for the relayed sink.

 Since passive events can duplicate those generate by FBSimulatorControl callers,
 this class also de-duplicates events.
 */
@interface FBSimulatorEventRelay : NSObject <FBSimulatorEventSink>

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

/**
 The current Simulator Connection.
 */
@property (nonatomic, strong, nullable, readonly) FBSimulatorConnection *connection;

@end

NS_ASSUME_NONNULL_END
