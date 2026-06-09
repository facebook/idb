/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDeviceIO.h>

@interface SimDeviceIO (Removed)

/**
 Removed in Xcode 27 (CoreSimulator 1155.4). The consumer attach/detach entry
 points and the +ioForSimDevice: factory are gone; the surviving IO surface is
 reached via -ioPorts and the SimDisplayIOSurfaceRenderable / SimDisplayRenderable
 protocols (see FBFramebuffer). Not called by idb/FBSimulatorControl.
 */
+ (id)ioForSimDevice:(id)arg1;
- (void)detachConsumer:(id)arg1 fromPort:(id)arg2;
- (void)attachConsumer:(id)arg1 withUUID:(id)arg2 toPort:(id)arg3 errorQueue:(id)arg4 errorHandler:(id)arg5;

@end
