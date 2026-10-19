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
+ (nullable NSNumber *)matchesStringValue:(nullable id)value expected:(NSString *)expected error:(NSError **)error NS_SWIFT_NAME(matchesString(_:expected:));
/// A copy of `value` made only of plain Foundation values: strings, numbers of the kind the runtime answered with,
/// dictionaries, arrays and null. Read under the runtime guard, so a value that raises when read fails the copy rather
/// than the process.
+ (nullable id)plainValueOf:(nullable id)value error:(NSError **)error NS_SWIFT_NAME(plainValue(of:));
@end

NS_ASSUME_NONNULL_END
