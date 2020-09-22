/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Commands to perform on a Simulator, related to photos/videos on the device
 */
@protocol FBSimulatorMediaCommands <NSObject, FBiOSTargetCommand>

/**
 Add media files to the simulator

 @param mediaFileURLs local paths to the media files to add
 @return A future that resolves when the media has been added.
 */
- (FBFuture<NSNull *> *)addMedia:(NSArray<NSURL *> *)mediaFileURLs;

/**
 Returns a Predicate that matches against video file paths.
 @return A predicate that matches against video file paths.
 */
+ (NSPredicate *)predicateForVideoPaths;

/**
 Returns a Predicate that matches against photo file paths.
 @return A predicate that matches against photo file paths.
 */
+ (NSPredicate *)predicateForPhotoPaths;

/**
 Returns a Predicate that matches against contact file paths.
 @return A predicate that matches against contact file paths.
 */
+ (NSPredicate *)predicateForContactPaths;
/**
 Returns a Predicate that matches against photo and video paths.
 @return A predicate that matches against photo and video paths.
 */
+ (NSPredicate *)predicateForMediaPaths;

@end

/**
 The implementation of the FBSimulatorMediaCommands instance.
 */
@interface FBSimulatorMediaCommands : NSObject <FBSimulatorMediaCommands>

@end

NS_ASSUME_NONNULL_END
