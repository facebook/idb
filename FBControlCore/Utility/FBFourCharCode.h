/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Human-readable rendering of a FourCC (four-character code, such as a CoreVideo
 pixel format). Returns the literal four ASCII characters when every byte is
 printable ASCII (0x20–0x7e, i.e. excludes NUL, control bytes, DEL, and any
 high-bit byte); otherwise falls back to an `0x`-prefixed 8-digit hex string so
 the result is always safe to log.

 This is a non-deprecated, drop-in replacement for `UTCreateStringForOSType`.

 @note When working in Swift code, prefer the `OSType.fourCharCodeString`
 computed property over this function. This C function exists solely so that
 Objective-C callers can share the same logic.

 @param code the FourCC / OSType to render.
 @return a string representation that is always safe to log.
 */
NSString *FBStringFromFourCharCode(OSType code);

NS_ASSUME_NONNULL_END
