/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

/**
 As of Xcode 27 (CoreSimulator 1155.4) this protocol is vended by CoreSimDeviceIO
 (re-exported by CoreSimulator), not SimulatorKit. Declaration retained here; not
 referenced by idb/FBSimulatorControl (it was a delegate of the now-removed
 framebuffer / video-writer classes).
 */
@protocol SimDisplayResizeableRenderable <FoundationXPCProtocolProxyable>
- (void)didChangeOptimizedDisplaySize:(struct CGSize)arg1;
- (void)didChangeDisplaySize:(struct CGSize)arg1;
@end
