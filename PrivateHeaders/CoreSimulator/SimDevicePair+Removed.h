/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDevicePair.h>

@interface SimDevicePair (Removed)

/**
 Removed in Xcode 27 (CoreSimulator 1155.4). Internal XPC request/notification
 plumbing, mirroring the same removals on SimDevice. Not called by
 idb/FBSimulatorControl.
 */
- (struct NSMutableDictionary *)newDevicePairNotification;
- (struct NSMutableDictionary *)createXPCNotification:(id)arg1;
- (struct NSMutableDictionary *)createXPCRequest:(id)arg1;

@end
