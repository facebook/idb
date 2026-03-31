/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Additional Predicates for FBControlCore.
 */
@interface NSPredicate (FBControlCore)

/**
 Returns a that will filter out null/NSNull values.
 */
+ (nonnull NSPredicate *)notNullPredicate;

@end
