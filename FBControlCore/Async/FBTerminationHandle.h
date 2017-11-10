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

@class FBFuture;

/**
 Extensible Diagnostic Name Enumeration.
 */
typedef NSString *FBTerminationHandleType NS_EXTENSIBLE_STRING_ENUM;

/**
 Simple protocol that allows asynchronous operations to be terminated.
 */
@protocol FBTerminationHandle <NSObject>

/**
 Terminates the asynchronous operation.
 */
- (void)terminate;

/**
 The Type of Termination Handle.
 */
@property (nonatomic, copy, readonly) FBTerminationHandleType handleType;

@end

/**
 A Termination Handle that can optionally be awaited for completions
 */
@protocol FBTerminationAwaitable <FBTerminationHandle>

/**
 A Future that resolves when the operation has completed.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *completed;

@end

/**
 Re-Names an existing awaitable.
 Useful when a lower-level awaitable should be hoisted to a higher-level naming.

 @param awaitable the awaitable to wrap
 @param handleType the handle to apply.
 @return a new Termination Awaitable.
 */
extern id<FBTerminationAwaitable> FBTerminationAwaitableRenamed(id<FBTerminationAwaitable> awaitable, FBTerminationHandleType handleType);

NS_ASSUME_NONNULL_END
