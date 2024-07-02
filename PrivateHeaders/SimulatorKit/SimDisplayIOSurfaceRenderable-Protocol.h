/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The underlying implementation is `ROCKRemoteProxy` and requesting the objects actually
 performs call to some service. The selector object may and may not exists,
 so checks like `[surface respondsToSelector: @selector(ioSurface)]` may return true, because
 this selector exists in proxy implementation, but underlying object may still not implement that selector
 and we will receive nil result.
 
 To be 100% sure we calling both methods (with plural underlying implementation and not) and one of the implementation
 will succeed.
 */
@protocol SimDisplayIOSurfaceRenderable <FoundationXPCProtocolProxyable>

/**
 In Xcode 8, this is an xpc_object_t
 In Xcode 9, this is an IOSurfaceRef.

 If the host is running macOS 10.12 or greater an IOSurfaceRef is toll-free-bridged to an IOSurface *object*.
 This is an Objective-C wrapper to the CoreFoundation IOSurfaceRef.

 Consumers should take this into account.
 */
@property (readonly, nullable, nonatomic) id ioSurface;

/**
 In Xcode 13.2 ioSurface was splitted to two surfaces. Use `framebufferSurface` as primary implementation.
 */
@property (readonly, nullable, nonatomic) id framebufferSurface;

/**
 We do not actually use this, but still worth to know that is exists.
 This clips image for devices with face id so image is not square, but in the shape of iPhone with notch
 */
@property (readonly, nullable, nonatomic) id maskedFramebufferSurface;

// Added in Xcode 9 as -[SimDeviceIOClient attachConsumer:] methods have been removed.
- (void)unregisterIOSurfaceChangeCallbackWithUUID:(NSUUID *)arg1;
- (void)registerCallbackWithUUID:(NSUUID *)arg1 ioSurfaceChangeCallback:(void (^)(id))arg2;

// Callbacks was slightly renamed in Xcode 13.2 to address two surfaces instead of one.
- (void)unregisterIOSurfacesChangeCallbackWithUUID:(NSUUID *)arg1;
- (void)registerCallbackWithUUID:(NSUUID *)arg1 ioSurfacesChangeCallback:(void (^)(id))arg2;

@end

NS_ASSUME_NONNULL_END
