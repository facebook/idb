/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <SimulatorKit/SimScreen-Protocol.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The IO-port "descriptor" that vends simulator displays in Xcode 27's
 Swift-rewritten SimulatorKit (reverse-engineered; replaces the removed
 `SimDisplayRenderable` descriptor conformance).

 Reached exactly like the legacy path: walk `device.io.ioPorts` and ask each
 `id<SimDeviceIOPortInterface>` for its `descriptor`. On Xcode 27 the descriptor
 conforms to `SimScreenAdapter` instead of `SimDisplayRenderable`.
 */
@protocol SimScreenAdapter <NSObject>

/**
 Asynchronously enumerates the displays attached to this adapter. The completion
 handler is invoked on `queue` with the available `SimScreen`s (or an error).
 Pick the screen whose `-isDefault` is YES (fallback: first).
 */
- (void)enumerateScreensWithCompletionQueue:(dispatch_queue_t)queue
                          completionHandler:(void (^)(NSArray<id<SimScreen>> * _Nullable screens, NSError * _Nullable error))completionHandler
  NS_SWIFT_NAME(enumerateScreens(completionQueue:completionHandler:));

/**
 Adapter lifecycle callbacks for hot-plug of displays. Guard with
 `respondsToSelector:` before use.
 */
- (void)registerScreenAdapterCallbacksWithUUID:(NSUUID *)uuid
                                 callbackQueue:(dispatch_queue_t)queue
                       screenConnectedCallback:(void (^)(id<SimScreen> screen))screenConnectedCallback
                  screenWillDisconnectCallback:(void (^)(id<SimScreen> screen))screenWillDisconnectCallback;

@end

NS_ASSUME_NONNULL_END
