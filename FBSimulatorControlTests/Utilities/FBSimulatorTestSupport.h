/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/// Helpers that construct an `FBSimulator` instance suitable for unit tests.
///
/// The unit-test path is intended to never reach production code that touches
/// the real `SimDevice`; the only thing the returned simulator needs to do is
/// expose its `commandCache` so tests can pre-register a wrapping command class
/// (see `FBTargetCommandCache.register(_:as:)`). The returned simulator's
/// `device`-derived properties are NOT guaranteed to be correct and must not
/// be exercised on the test path.
///
/// Lives in Obj-C because the `FBSimulator` designated initializer takes a
/// `SimDevice *`, but at runtime it only reads `-UDID.UUIDString`. Casting our
/// stub through `id` here lets the type checker accept the substitution
/// without us having to depend on CoreSimulator from Swift.
@interface FBSimulatorTestSupport : NSObject

/// Builds an `FBSimulator` whose `commandCache` is empty and ready for
/// `register(_:as:)` calls. Do NOT exercise `device`-derived properties on the
/// returned simulator — they are stub-backed and unsafe.
+ (FBSimulator *)testableSimulator;

@end

NS_ASSUME_NONNULL_END
