/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Parses the same flag/value pairs consumed by the accessibility command. */
NSDictionary<NSString *, id> *FBAXBridgeRequestFromArguments(NSString *action, NSArray<NSString *> *arguments);

void FBAXBridgePrepareRuntime(void);

NSDictionary<NSString *, id> *FBAXBridgeHandleRequestData(
  NSData *data,
  BOOL *_Nullable shutdownRequested);

NS_ASSUME_NONNULL_END
