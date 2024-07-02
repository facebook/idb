/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBiOSTargetOperation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBDataConsumer;

/**
 Defines an interface for Video Recording.
 */
@protocol FBVideoRecordingCommands <NSObject, FBiOSTargetCommand>

/**
 Starts the Recording of Video to a File on Disk.

 @param filePath the filePath to write to.
 @return A Future, wrapping the recording session.
 */
- (FBFuture<id<FBiOSTargetOperation>> *)startRecordingToFile:(NSString *)filePath;

/**
 Stops the Recording of Video.

 @return A Future, resolved when recording has stopped
 */
- (FBFuture<NSNull *> *)stopRecording;

@end

NS_ASSUME_NONNULL_END
