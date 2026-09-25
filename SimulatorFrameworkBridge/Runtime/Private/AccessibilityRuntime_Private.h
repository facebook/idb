/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Runs synchronously off the main queue, rethrowing any exception on the calling thread. */
void FBAXBridgeRunOffMainQueue(dispatch_block_t block);

NS_ASSUME_NONNULL_END
