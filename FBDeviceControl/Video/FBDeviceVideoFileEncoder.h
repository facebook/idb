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

@class AVCaptureSession;
@protocol FBControlCoreLogger;

/**
 Encodes Device Video to a File, using an AVCaptureSession
 */
@interface FBDeviceVideoFileEncoder : NSObject

/**
 Creates a Video Encoder with the provided Parameters.

 @param session the Session to record from.
 @param filePath the File Path to record to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 */
+ (nullable instancetype)encoderWithSession:(AVCaptureSession *)session filePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

/**
 Starts the Video Encoder.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)startRecordingWithError:(NSError **)error;

/**
 Stops the Video Encoder.
 If the encoder is running, it will block until the Capture Session has been torn down.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)stopRecordingWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
