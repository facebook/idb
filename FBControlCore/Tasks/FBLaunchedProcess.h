/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An in-memory representation of a launched process.
 Can be inspected for completion.
 */
@protocol FBLaunchedProcess <NSObject>

/**
 The Process Idenfifer of the Launched Process.
 */
@property (nonatomic, assign, readonly) pid_t processIdentifier;

/**
 A future that resolves with the exit code upon termination
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *exitCode;

@end

NS_ASSUME_NONNULL_END
