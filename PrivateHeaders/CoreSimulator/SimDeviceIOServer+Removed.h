/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDeviceIOServer.h>

@interface SimDeviceIOServer (Removed)

/**
 Removed in Xcode 27 (CoreSimulator 1155.4). The pre-resolved display-descriptor
 accessors and -loadAllBundles are gone (-unloadAllBundles remains). The main
 display surface is now discovered by walking -ioPorts and matching the
 SimDisplayDescriptorState displayClass (see FBFramebuffer). Not called by
 idb/FBSimulatorControl.
 */
- (id)tvOutDisplayDescriptorState;
- (id)mainDisplayDescriptorState;
- (id)integratedDisplayDescriptorState;
- (BOOL)loadAllBundles;

@end
