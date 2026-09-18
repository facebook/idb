/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Contains Foundation selector exceptions without requiring a private runtime binding. */
@interface FBAXWireValue : NSObject
+ (nullable NSNumber *)booleanFromValue:(nullable id)value error:(NSError **)error NS_SWIFT_NAME(boolean(from:));
+ (nullable NSString *)formattedDescriptionOfValue:(nullable id)value error:(NSError **)error NS_SWIFT_NAME(formattedDescription(of:));
@end

NS_ASSUME_NONNULL_END
