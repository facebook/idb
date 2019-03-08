/**
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

@end

/**
 The implementation of the FBSimulatorMediaCommands instance.
 */
@interface FBSimulatorMediaCommands : NSObject <FBSimulatorMediaCommands>

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
