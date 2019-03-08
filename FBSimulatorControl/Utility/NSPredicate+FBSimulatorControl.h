/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Additional Predicates for FBSimulatorControl.
 */
@interface NSPredicate (FBSimulatorControl)

/**
 Returns a Predicate that matches against video file paths.
 */
+ (NSPredicate *)predicateForVideoPaths;

/**
 Returns a Predicate that matches against photo file paths.
 */
+ (NSPredicate *)predicateForPhotoPaths;

/**
 Returns a Predicate that matches against photo and video paths.
 */
+ (NSPredicate *)predicateForMediaPaths;

@end

NS_ASSUME_NONNULL_END
