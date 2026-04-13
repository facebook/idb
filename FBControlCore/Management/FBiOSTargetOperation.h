/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

/**
 Creates a new operation.

 @param completed the completion future
 @return an Operation wrapping the Future
 */
extern id _Nonnull FBiOSTargetOperationFromFuture(FBFuture<NSNull *> * _Nonnull completed);
