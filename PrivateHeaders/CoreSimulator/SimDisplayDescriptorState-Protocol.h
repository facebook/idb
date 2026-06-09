/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/FoundationXPCProtocolProxyable-Protocol.h>
#import <CoreSimulator/SimDeviceIOPortDescriptorState-Protocol.h>

/**
 As of Xcode 27 (CoreSimulator 1155.4) this protocol is vended by CoreSimDeviceIO
 (re-exported by CoreSimulator). Declaration retained here; the display descriptor
 returned from an IO port conforms to it at runtime (FBFramebuffer reads
 -displayClass to find the main display), so the move is transparent.
 */
@protocol SimDisplayDescriptorState <FoundationXPCProtocolProxyable, SimDeviceIOPortDescriptorState>
@property (nonatomic, readonly) unsigned int defaultPixelFormat;
@property (nonatomic, readonly) unsigned int defaultHeightForDisplay;
@property (nonatomic, readonly) unsigned int defaultWidthForDisplay;
@property (nonatomic, readonly) unsigned short displayClass;
@end
