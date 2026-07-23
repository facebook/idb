/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Opaque properties payload delivered by `-[SimScreen registerScreenCallbacksWithUUID:...]`
 via its `propertiesChangedCallback`.

 Introduced in Xcode 27's Swift rewrite of SimulatorKit (reverse-engineered).
 We do not consume any members today; the protocol exists so the callback
 block type-checks and so we can forward-declare it where needed.
 */
@protocol SimScreenProperties <NSObject>
@end

NS_ASSUME_NONNULL_END
