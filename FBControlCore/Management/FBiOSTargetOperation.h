/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

/**
 A protocol that represents an operation of indeterminate length.
 */
@protocol FBiOSTargetOperation <NSObject>

/**
 A Optional Future that resolves when the operation has completed.
 */
@property (nonnull, nonatomic, readonly, strong) FBFuture<NSNull *> *completed;

@end

/**
 Creates a new operation.

 @param completed the completion future
 @return an Operation wrapping the Future
 */
extern id<FBiOSTargetOperation> _Nonnull FBiOSTargetOperationFromFuture(FBFuture<NSNull *> * _Nonnull completed);

// FBiOSTargetOperation_Wrapper is now implemented in Swift.
