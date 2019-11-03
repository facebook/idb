/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAppleSimctlCommandExecutor;
@class FBFramebuffer;
@class FBVideoEncoderConfiguration;
@protocol FBControlCoreLogger;
@protocol FBSimulatorEventSink;

/**
 Controls the Recording of a Simulator's Framebuffer to a Video.
 */
@interface FBSimulatorVideo : NSObject <FBiOSTargetContinuation>

/**
 The Designated Initializer.

 @param configuration the configuration to use for encoding.
 @param framebuffer the Framebuffer to consume
 @param logger the logger object to log events to, may be nil.
 @return a new FBSimulatorVideo instance.
 */
+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration framebuffer:(FBFramebuffer *)framebuffer logger:(id<FBControlCoreLogger>)logger;

/**
 The Designated Initializer, for doing simulator video recording using Apple's simctl

 @param simctlExecutor the simctl executor
 @param logger the logger object to log events to, may be nil.
 @return a new FBSimulatorVideo instance.
 */
+ (instancetype)videoWithSimctlExecutor:(FBAppleSimctlCommandExecutor *)simctlExecutor logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Starts Recording Video.

 @param filePath the (optional) file path to record to. If nil is provided, a default path will be used.
 @return A Future that resolves when recording has started.
 */
- (FBFuture<NSNull *> *)startRecordingToFile:(nullable NSString *)filePath;

/**
 Stops Recording Video.

 @return A Future that resolves when recording has stopped.
 */
- (FBFuture<NSNull *> *)stopRecording;

@end

NS_ASSUME_NONNULL_END
