/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
