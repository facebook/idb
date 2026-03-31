/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorVideoStream_Testing.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A test double logger that captures all logged messages for assertion.
 */
@interface FBCapturingLogger : NSObject <FBControlCoreLogger>
@property (nonatomic, readonly, strong) NSMutableArray<NSString *> *messages;
@end

/**
 Creates an H264 CMSampleBuffer suitable for testing.
 The buffer is marked as data-ready.
 Caller is responsible for releasing with CFRelease.
 */
CMSampleBufferRef CreateH264SampleBuffer(void);

/**
 Creates an H264 CMSampleBuffer that is NOT data-ready.
 Used to simulate encoder warmup / starvation scenarios.
 Caller is responsible for releasing with CFRelease.
 */
CMSampleBufferRef CreateNotReadySampleBuffer(void);

/**
 Creates a FBSimulatorVideoStreamFramePusher_VideoToolbox configured for H264/AnnexB testing.
 Uses WriteFrameToAnnexBStream as the frame writer.
 */
FBSimulatorVideoStreamFramePusher_VideoToolbox *CreateTestVideoStreamPusher(id<FBControlCoreLogger> logger);

/**
 Wraps handleCompressedSampleBuffer:encodeStatus:infoFlags: to accept nullable CMSampleBufferRef.
 Swift cannot pass nil for CMSampleBuffer parameters, so this wrapper is needed.
 */
void HandleCompressedSampleBufferNullable(
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher,
  CMSampleBufferRef _Nullable sampleBuffer,
  OSStatus encodeStatus,
  VTEncodeInfoFlags infoFlags);

NS_ASSUME_NONNULL_END
