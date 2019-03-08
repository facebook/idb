/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SimDisplayIOSurfaceRenderable <FoundationXPCProtocolProxyable>

/**
 In Xcode 8, this is an xpc_object_t
 In Xcode 9, this is an IOSurfaceRef.

 If the host is running macOS 10.12 or greater an IOSurfaceRef is toll-free-bridged to an IOSurface *object*.
 This is an Objective-C wrapper to the CoreFoundation IOSurfaceRef.

 Consumers should take this into account.
 */
@property (readonly, nullable, nonatomic) id ioSurface;

// Added in Xcode 9 as -[SimDeviceIOClient attachConsumer:] methods have been removed.
- (void)unregisterIOSurfaceChangeCallbackWithUUID:(NSUUID *)arg1;
- (void)registerCallbackWithUUID:(NSUUID *)arg1 ioSurfaceChangeCallback:(void (^)(id))arg2;

@end

NS_ASSUME_NONNULL_END
