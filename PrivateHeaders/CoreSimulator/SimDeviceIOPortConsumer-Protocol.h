/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/FoundationXPCProtocolProxyable-Protocol.h>

@class NSString, NSUUID;

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): the IO-port
 consumer delegate protocol, used only by the removed framebuffer / video-writer
 classes. No longer present in any Xcode 27 framework and not referenced by
 idb/FBSimulatorControl. Header retained for reference and for building against
 <= Xcode 26.x; scheduled for removal.
 */
@protocol SimDeviceIOPortConsumer <FoundationXPCProtocolProxyable>
@property (nonatomic, readonly) NSUUID *consumerUUID;
@property (nonatomic, readonly, copy) NSString *consumerIdentifier;
@end
