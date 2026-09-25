/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSDictionary<NSString *, id> *FBNotificationCommandExceptionResult(
  NSString *operation,
  int (^NS_NOESCAPE run)(NSString *action, NSString *_Nullable bundleID, id gateway)
);
NS_ASSUME_NONNULL_END
