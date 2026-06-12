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
@class FBVideoStreamConfiguration;

/**
 An implementation of FBVideoStream, for Devices.
 */
@interface FBDeviceVideoStream : NSObject <FBVideoStream>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param session the Session to record from.
 @param configuration The configuration of the stream.
 @param logger the logger to log to.
 @param error an error out for any error that occurs.
 @return a new Video Encoder.
 */
+ (nullable instancetype)streamWithSession:(AVCaptureSession *)session configuration:(FBVideoStreamConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
