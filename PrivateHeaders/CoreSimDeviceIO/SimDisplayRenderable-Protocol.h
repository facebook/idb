/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/FoundationXPCProtocolProxyable-Protocol.h>

/**
 As of Xcode 27 (CoreSimulator 1155.4) this protocol is vended by
 CoreSimDeviceIO (re-exported by CoreSimulator), not SimulatorKit, which is now
 almost entirely Swift. The declaration is retained here unchanged: the IO-port
 descriptor still conforms to it at runtime and FBFramebuffer resolves it via
 -conformsToProtocol: / -respondsToSelector:, so the framework move is
 transparent. This header now lives in the CoreSimDeviceIO module.
 */
@protocol SimDisplayRenderable <FoundationXPCProtocolProxyable, NSObject>
@property (nonatomic, readonly) long long displaySizeInBytes;
@property (nonatomic, readonly) long long displayPitch;
@property (nonatomic, readonly) struct CGSize optimizedDisplaySize;
@property (nonatomic, readonly) struct CGSize displaySize;

// Added in Xcode 9 as -[SimDeviceIOClient attachConsumer:] methods have been removed.
- (void)unregisterDamageRectanglesCallbackWithUUID:(NSUUID *)arg1;
/**
 The callback delivers the display regions that changed since the previous callback. Each element is
 an NSValue boxing a CGRect. This element type is a reverse-engineered convention: the underlying
 ROCKRemoteProxy declares only an untyped NSArray and does not enforce it, so consumers must still
 decode each element defensively. An empty array is a valid "surface changed, no rects reported"
 signal and is still delivered.
 */
- (void)registerCallbackWithUUID:(NSUUID *)arg1 damageRectanglesCallback:(void (^)(NSArray<NSValue *> *))arg2;

@end
