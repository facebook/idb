/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A class for wrapping `dispatch_source` with some conveniences.
 */
@interface FBDispatchSourceNotifier : NSObject

#pragma mark Constructors

/**
 A future that resolves when the given process identifier terminates.

 @param processIdentifier the process identifier to observe.
 @return a Future that resolves when the process identifier terminates, with the process identifier.
 */
+ (FBFuture<NSNumber *> *)processTerminationFutureNotifierForProcessIdentifier:(pid_t)processIdentifier;

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
