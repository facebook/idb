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
@interface FBUploadMediaStrategy : NSObject

/**
 Creates a Strategy for the provided Simulator.

 @param simulator the Simulator to launch on.
 @return a new Add Video Strategy.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

/**
 Uploads photos or videos to the Camera Roll of the Simulator.

 @param mediaPaths an NSArray<NSString *> of File Paths for the Videos to Upload.
 @param error an error out for any error that occurs.
 @return YES if the upload was successful, NO otherwise.
 */
- (BOOL)uploadMedia:(NSArray<NSString *> *)mediaPaths error:(NSError **)error;

/**
 Adds a Video to the Camera Roll.
 Will polyfill to the 'Camera App Upload' hack, if required

 @param paths an Array of paths of videos to upload.
 @param error an error out for any error that occurs.
 @return YES if the upload was successful, NO otherwise.
 */
- (BOOL)uploadVideos:(NSArray<NSString *> *)paths error:(NSError **)error;

/**
 Uploads photos to the Camera Roll of the Simulator

 @param photoPaths photoPaths an NSArray<NSString *> of File Paths for the Photos to Upload.
 @param error an error out for any error that occurs.
 @return YES if the upload was successful, NO otherwise.
 */
- (BOOL)uploadPhotos:(NSArray<NSString *> *)photoPaths error:(NSError **)error;


@end

NS_ASSUME_NONNULL_END
