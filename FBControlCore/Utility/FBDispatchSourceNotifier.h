/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A class for wrapping `dispatch_source` with some conveniences.
 */
@interface FBDispatchSourceNotifier : NSObject

#pragma mark Constructors

/**
 Creates and returns an `FBDispatchSourceNotifier` that will call the `handler` when the provided `processIdentifier` quits

 @param processIdentifier the Process Identifier of the Process to Monitor
 @param queue the queue to call back on.
 @param handler the handler to call when the process exits
 */
+ (instancetype)processTerminationNotifierForProcessIdentifier:(pid_t)processIdentifier queue:(dispatch_queue_t)queue handler:(void (^)(FBDispatchSourceNotifier *))handler;

/**
 Creates and returns an `FBDispatchSourceNotifier` that will call the `handler` at a provided timing interval.

 @param timeInterval the time interval to wait for.
 @param queue the queue to call back on.
 @param handler the handler to call when the process exits
 */
+ (instancetype)timerNotifierNotifierWithTimeInterval:(uint64_t)timeInterval queue:(dispatch_queue_t)queue handler:(void (^)(FBDispatchSourceNotifier *))handler;

#pragma mark Public Methods

/**
 Stops the Notifier.
 */
- (void)terminate;

#pragma mark Properties

/**
 The Wrapped Dispatch Source.
 */
@property (nonatomic, strong, nullable, readonly) dispatch_source_t dispatchSource;

@end

NS_ASSUME_NONNULL_END
