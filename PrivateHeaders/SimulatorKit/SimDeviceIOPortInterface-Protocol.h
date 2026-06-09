/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

@class NSUUID;

/**
 As of Xcode 27 (CoreSimulator 1155.4) this protocol is vended by CoreSimDeviceIO
 (re-exported by CoreSimulator), not SimulatorKit, which is now almost entirely
 Swift. Declaration retained here; -[SimDeviceIOClient ioPorts] returns objects
 conforming to it at runtime (see FBFramebuffer), so the move is transparent.
 Eventual home: a CoreSimDeviceIO header group.
 */
@protocol SimDeviceIOPortInterface <FoundationXPCProtocolProxyable, NSObject>
@property (nonatomic, readonly) id descriptor;
@property (nonatomic, readonly) NSUUID *uuid;
@property (nonatomic, readonly) unsigned short ioPortClass;
@end
