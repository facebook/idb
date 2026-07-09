/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceObjC.h>

#import <SimulatorKit/SimScreenProperties-Protocol.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Represents a single simulator display in Xcode 27's Swift-rewritten SimulatorKit
 (reverse-engineered; replaces the removed `SimDisplayIOSurfaceRenderable` /
 `SimDisplayRenderable` protocols).

 Obtained by enumerating an `id<SimScreenAdapter>` (see `SimScreenAdapter-Protocol.h`),
 which is itself vended from a `[port descriptor]` off `device.io.ioPorts`.

 All selectors below are confirmed present as Objective-C selectors / `@objc`
 getters in `Contents/SharedFrameworks/SimulatorKit.framework`.
 */
@protocol SimScreen <NSObject>

/**
 The raw, unmasked framebuffer surface (maps to the old `framebufferSurface`).
 */
@property (readonly, nullable, nonatomic) IOSurface *unmaskedSurface;

/**
 The framebuffer surface masked to the device's physical shape (notch / rounded
 corners), maps to the old `maskedFramebufferSurface`.
 */
@property (readonly, nullable, nonatomic) IOSurface *maskedSurface;

/**
 YES for the simulator's main/default display.
 */
@property (readonly, nonatomic) BOOL isDefault;

/**
 Unified per-screen callback registration (replaces the removed
 `registerCallbackWithUUID:ioSurfacesChangeCallback:` +
 `registerCallbackWithUUID:damageRectanglesCallback:`).

 - `frameCallback` fires per presented frame (vsync); no payload.
 - `surfacesChangedCallback` fires when the backing IOSurface(s) change, with the
   new `(unmasked, masked)` surfaces.
 - `propertiesChangedCallback` fires when display properties change.
 */
- (void)registerScreenCallbacksWithUUID:(NSUUID *)uuid
                          callbackQueue:(dispatch_queue_t)queue
                          frameCallback:(void (^)(void))frameCallback
                surfacesChangedCallback:(void (^)(IOSurface * _Nullable unmaskedSurface, IOSurface * _Nullable maskedSurface))surfacesChangedCallback
              propertiesChangedCallback:(void (^)(id<SimScreenProperties> properties))propertiesChangedCallback
  NS_SWIFT_NAME(registerScreenCallbacks(uuid:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:));

/**
 Tears down a previously registered set of callbacks. Guard with
 `respondsToSelector:` before calling — the exact selector is not guaranteed
 across betas.
 */
- (void)unregisterScreenCallbacksWithUUID:(NSUUID *)uuid NS_SWIFT_NAME(unregisterScreenCallbacks(uuid:));

@end

NS_ASSUME_NONNULL_END
