/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorSession;

@interface FBSimulatorVideoUploader : NSObject

/**
 Create a new FBSimulatorVideoRecorder for the provided sessions.

 @param session the session to whose simulator the videos will be uploaded to.
 @return a new video uploader instance.
 */
+ (instancetype)forSession:(FBSimulatorSession *)session;

/**
 Uploads videos to the Camera Roll of the Simulator

 @param videoPaths an NSArray<NSString *> of file paths for the videos to upload.
 @param error the error out, for any error that occurred.
 @returns YES if the videos were uploaded successfully, NO otherwise.
 */
- (BOOL)uploadVideos:(NSArray *)videoPaths error:(NSError **)error;

@end
