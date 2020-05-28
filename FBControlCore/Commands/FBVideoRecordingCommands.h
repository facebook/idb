/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBDataConsumer;

/**
 The Termination Handle Type for an Recording Operation.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeVideoRecording;

/**
 Defines an interface for Video Recording.
 */
@protocol FBVideoRecordingCommands <NSObject, FBiOSTargetCommand>

/**
 Starts the Recording of Video to a File on Disk.

 @param filePath an optional filePath to write to.
 @return A Future, wrapping the recording session.
 */
- (FBFuture<id<FBiOSTargetContinuation>> *)startRecordingToFile:(nullable NSString *)filePath;

/**
 Stops the Recording of Video.

 @return A Future, resolved when recording has stopped
 */
- (FBFuture<NSNull *> *)stopRecording;

@end

NS_ASSUME_NONNULL_END
