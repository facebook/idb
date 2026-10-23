/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** SpringBoard's lock state, as its lock status call reports it. */
@interface FBLockScreenStatus : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithLocked:(BOOL)locked passcodeEnabled:(BOOL)passcodeEnabled NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) BOOL locked;
@property (nonatomic, readonly) BOOL passcodeEnabled;
@end

typedef NS_ENUM(NSUInteger, FBLockScreenRequestOutcome) {
  /** SpringBoard answered the request as done. */
  FBLockScreenRequestOutcomeCompleted,
  /** SpringBoard did not answer within the timeout. */
  FBLockScreenRequestOutcomeTimedOut,
  /** SpringBoard could not be asked: the framework, class or method is missing, or the call raised. */
  FBLockScreenRequestOutcomeUnavailable,
};

/** Reads and changes SpringBoard's lock state. */
@interface FBLockScreenClient : NSObject

/** The current state, or nil (logged) when SpringBoard cannot be asked. */
+ (nullable FBLockScreenStatus *)currentStatus;

/**
 * Waits up to `timeout` for SpringBoard to report `locked`, woken by its lock state notification rather
 * than by polling, then returns the state it reports, which may still differ. Nil as soon as a read fails.
 */
+ (nullable FBLockScreenStatus *)statusAfterWaitingForLocked:(BOOL)locked timeout:(NSTimeInterval)timeout;

+ (FBLockScreenRequestOutcome)lockWithTimeout:(NSTimeInterval)timeout;

/**
 * Asks SpringBoard, through its accessibility server, to unlock its UI. The request has no answer, so it
 * is `completed` once sent; the lock state shows whether SpringBoard acted on it.
 */
+ (FBLockScreenRequestOutcome)requestUnlock;

@end

NS_ASSUME_NONNULL_END
