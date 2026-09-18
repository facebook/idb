/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityResponseEncoder.h"

@implementation FBAXResponseEncoder

+ (NSData *)dataForObject:(id)object
{
  @try {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
  } @catch (NSException *exception) {
    NSLog(@"[AccessibilityService] response serialization raised: %@", exception);
    return nil;
  }
}

@end
