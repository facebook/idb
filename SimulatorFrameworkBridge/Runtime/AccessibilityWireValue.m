/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityWireValue.h"

static void FBAXWireValueException(NSException *exception, NSError **error)
{
  NSLog(@"[AccessibilityService] answering a request raised: %@", exception);
  if (error) {
    *error = [NSError errorWithDomain:@"FBAXRuntimeException" code:1 userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: exception.name}];
  }
}

@implementation FBAXWireValue

+ (NSNumber *)booleanFromValue:(id)value error:(NSError **)error
{
  @try {
    return @([value boolValue]);
  } @catch (NSException *exception) {
    FBAXWireValueException(exception, error);
    return nil;
  }
}

+ (NSString *)formattedDescriptionOfValue:(id)value error:(NSError **)error
{
  @try {
    return [NSString stringWithFormat:@"%@", value];
  } @catch (NSException *exception) {
    FBAXWireValueException(exception, error);
    return nil;
  }
}

@end
