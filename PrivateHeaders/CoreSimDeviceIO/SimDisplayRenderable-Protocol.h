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
 Historically named for per-region "damage" geometry, this is in practice a per-frame change
 signal only. Apple's render server brands it the "old-style damageRect callback"; on modern
 CoreSimulator the server is a whole-frame compositor that computes no changed regions and always
 invokes the block with an empty array (the array type is a reverse-engineered `NSArray<NSValue *>`
 convention over an untyped `NSArray`, so any element must still be decoded defensively). Treat an
 invocation as "a new frame was rendered", not as geometry. Retained as a fallback; prefer the
 new-style per-present callback where available.
 */
- (void)registerCallbackWithUUID:(NSUUID *)arg1 damageRectanglesCallback:(void (^)(NSArray<NSValue *> *))arg2;

@end
