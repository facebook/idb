/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBKeyedArchiveReference : NSObject
/** The archive pool index, or nil for a non-reference or unavailable private accessors. */
+ (nullable NSNumber *)indexOfObject:(nullable id)object NS_SWIFT_NAME(index(of:));
@end

NS_ASSUME_NONNULL_END
