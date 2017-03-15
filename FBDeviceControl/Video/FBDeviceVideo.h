/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;

/**
 A Class for obtaining Video Configuration for a Device.
 */
@interface FBDeviceVideo : NSObject <FBVideoRecordingSession>

/**
 A Factory method for obtaining the Video for a Device.

 @param device the Device.
 @param filePath the location of the video to record to, will be deleted if it already exists.
 @param error an error out for any error that occurs.
 */
+ (nullable instancetype)videoForDevice:(FBDevice *)device filePath:(NSString *)filePath error:(NSError **)error;

/**
 Starts Recording the Video for a Device.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)startRecordingWithError:(NSError **)error;

/**
 Stops Recording the Video for a Device.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)stopRecordingWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
