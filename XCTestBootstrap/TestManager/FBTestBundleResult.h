/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBCrashLog;
@class XCTestBootstrapError;

/**
 A Class-Cluster representing a completed test bundle result.
 */
@interface FBTestBundleResult : NSObject

/**
 A Successful Result.
 */
+ (instancetype)success;

/**
 A Client requested a disconnect.
 */
+ (instancetype)clientRequestedDisconnect;

/**
 A Result that represents a Test Bundle crashing during a test run.
 */
+ (instancetype)bundleCrashedDuringTestRun:(FBCrashLog *)crash;

/**
 A Failure Result.
 */
+ (instancetype)failedInError:(XCTestBootstrapError *)error;

/**
 YES if the Test Manager finished successfully, NO otherwise.
 */
@property (nonatomic, assign, readonly) BOOL didEndSuccessfully;

/**
 The Underlying error.
 */
@property (nonatomic, strong, nullable, readonly) NSError *error;

/**
 A Diagnostic for a crash.
 */
@property (nonatomic, strong, nullable, readonly) FBCrashLog *crash;

@end

NS_ASSUME_NONNULL_END
