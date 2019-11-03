/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSPredicate+FBControlCore.h"

@implementation NSPredicate (FBControlCore)

#pragma mark Public

+ (NSPredicate *)notNullPredicate
{
  return [NSPredicate predicateWithFormat:@"self != nil"];
}

@end
