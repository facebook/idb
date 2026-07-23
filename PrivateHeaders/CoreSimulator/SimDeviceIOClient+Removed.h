/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDeviceIOClient.h>

@interface SimDeviceIOClient (Removed)

/**
 Removed in Xcode 27 (CoreSimulator 1155.4). Consumer detach is gone alongside
 the SimDeviceIO attach/detach API. Not called by idb/FBSimulatorControl.
 */
- (void)detachConsumer:(id)arg1 fromPort:(id)arg2;

@end
