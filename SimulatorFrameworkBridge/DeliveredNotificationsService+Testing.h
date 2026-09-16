/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Reads from `directory` instead of the device's notification store, or restores it with nil. */
void FBDeliveredNotificationsSetDirectoryForTesting(NSString *_Nullable directory);

/** Uses `timeout` for center replies, or restores the default with 0. */
void FBDeliveredNotificationsSetTimeoutForTesting(NSTimeInterval timeout);

NS_ASSUME_NONNULL_END
