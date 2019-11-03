/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBSimulatorControl/FBSimulatorEventSink.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An Event Sink that can be changed with an Event Sink of the User's choosing at Runtime.
 This allows th
 */
@interface FBMutableSimulatorEventSink : NSObject <FBSimulatorEventSink>

/**
 The Event Sink to currently use, may be nil
 */
@property (nonatomic, strong, readwrite) id<FBSimulatorEventSink> eventSink;

@end

NS_ASSUME_NONNULL_END
