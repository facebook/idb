/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class AVCaptureSession;

/**
 Encodes Device Video to a File, using an AVCaptureSession
 */
@interface FBVideoFileWriter : NSObject

#pragma mark Initializers

/**
 Creates a Video Encoder with the provided Parameters.

 @param session the Session to record from.
 @param filePath the File Path to record to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 */
+ (nullable instancetype)writerWithSession:(AVCaptureSession *)session filePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

#pragma mark Public Methods

/**
 Starts the Video Encoder.

 @return A future that resolves when encoding has started.
 */
- (FBFuture<NSNull *> *)startRecording;

/**
 Stops the Video Encoder.
 If the encoder is running, it will block until the Capture Session has been torn down.

 @return A future that resolves when encoding has stopped.
 */
- (FBFuture<NSNull *> *)stopRecording;

/**
 A Future that resolves when the recording has completed.

 @return A future that resolves when encoding has stopped.
 */
- (FBFuture<NSNull *> *)completed;

@end

NS_ASSUME_NONNULL_END
