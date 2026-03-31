/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBAppleSimctlCommandExecutor;
@protocol FBControlCoreLogger;

/**
 Implementations of recording a Simulator's screen to a video file.
 */
@interface FBSimulatorVideo : NSObject <FBiOSTargetOperation>

/**
 The Designated Initializer, for doing simulator video recording using Apple's simctl

 @param simctlExecutor the simctl executor
 @param filePath the file path to write to.
 @param logger the logger object to log events to, may be nil.
 @return a new FBSimulatorVideo instance.
 */
+ (nonnull instancetype)videoWithSimctlExecutor:(nonnull FBAppleSimctlCommandExecutor *)simctlExecutor filePath:(nonnull NSString *)filePath logger:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Starts recording video.

 @return A Future that resolves when recording has started.
 */
- (nonnull FBFuture<NSNull *> *)startRecording;

/**
 Stops recording video.

 @return A Future that resolves when recording has stopped.
 */
- (nonnull FBFuture<NSNull *> *)stopRecording;

@end
