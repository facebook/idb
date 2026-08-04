/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/FoundationXPCProtocolProxyable-Protocol.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The new-style ("SimScreen") display-callback surface vended by CoreSimDeviceIO. The IO-port display
 descriptor conforms to this at runtime in addition to SimDisplayRenderable /
 SimDisplayIOSurfaceRenderable; FBFramebuffer resolves it via -conformsToProtocol: and prefers it
 over the old-style damageRectanglesCallback (which the render server itself brands "old-style").

 - frameCallback fires once per presented frame — the per-frame change signal a variable-frame-rate
   consumer needs, without the legacy damage-rect shape.
 - surfacesChangedCallback fires on surface (re)mount — a surface-identity change, and once at
   registration if a surface already exists — not per present. Its two args are the current
   (framebufferSurface, maskedFramebufferSurface): arg 0 is the primary surface to render; arg 1 is
   the notch/corner-masked variant, which we ignore (mirrors SimDisplayIOSurfaceRenderable's
   framebufferSurface / maskedFramebufferSurface). Both are IOSurfaceRef (toll-free bridged to
   IOSurface) and may be nil.
 - propertiesChangedCallback delivers an id<SimScreenProperties> (a CoreSimDeviceIO protocol);
   FBFramebuffer does not consume it.

 The block args are typed `id` rather than IOSurface / SimScreenProperties: the descriptor is a
 ROCKRemoteProxy (untyped remoting — see SimDisplayIOSurfaceRenderable-Protocol.h), so the seam
 confirms each value with a defensive runtime cast rather than trusting an unsound bridge. All three
 callbacks are delivered on callbackQueue.
 */
@protocol SimScreen <FoundationXPCProtocolProxyable>
- (void)registerScreenCallbacksWithUUID:(NSUUID *)arg1
                          callbackQueue:(dispatch_queue_t)arg2
                          frameCallback:(void (^)(void))arg3
                surfacesChangedCallback:(void (^)(id _Nullable, id _Nullable))arg4
              propertiesChangedCallback:(void (^)(id))arg5
    NS_SWIFT_NAME(registerScreenCallbacks(uuid:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:));
- (void)unregisterScreenCallbacksWithUUID:(NSUUID *)arg1 NS_SWIFT_NAME(unregisterScreenCallbacks(uuid:));

@end

NS_ASSUME_NONNULL_END
