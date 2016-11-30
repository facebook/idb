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

@class FBSimulator;

/**
 A Strategy for Adding a Video to a Simulator.
 */
@interface FBAddVideoStrategy : NSObject

/**
 Creates a Strategy for the provided Simulator.

 @param simulator the Simulator to launch on.
 @return a new Add Video Strategy.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

/**
 Adds a Video to the Camera Roll.
 Will polyfill to the 'Camera App Upload' hack, if required

 @param paths an Array of paths of videos to upload.
 @return YES if the upload was successful, NO otherwise.
 */
- (BOOL)addVideos:(NSArray<NSString *> *)paths error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
