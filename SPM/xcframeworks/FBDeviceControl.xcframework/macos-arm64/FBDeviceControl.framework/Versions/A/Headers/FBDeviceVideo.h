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
@class FBDevice;

/**
 A Class for obtaining Video Configuration for a Device.
 */
@interface FBDeviceVideo : NSObject <FBiOSTargetOperation>

#pragma mark Initializers

/**
 Obtains the AVCaptureSession for a Device.

 @param device the Device to obtain the Session for.
 @return A Capture Session if successful, nil otherwise.
 */
+ (FBFuture<AVCaptureSession *> *)captureSessionForDevice:(FBDevice *)device;

/**
 A Factory method for obtaining the Video for a Device.

 @param device the Device.
 @param filePath the location of the video to record to, will be deleted if it already exists.
 @return a Future wrapping the Device Video.
 */
+ (FBFuture<FBDeviceVideo *> *)videoForDevice:(FBDevice *)device filePath:(NSString *)filePath;

#pragma mark Public

/**
 Starts Recording the Video for a Device.

 @return a Future that resolves when recording has started.
 */
- (FBFuture<NSNull *> *)startRecording;

/**
 Stops Recording the Video for a Device.

 @return a Future that resolves when recording has stopped.
 */
- (FBFuture<NSNull *> *)stopRecording;

@end

NS_ASSUME_NONNULL_END
