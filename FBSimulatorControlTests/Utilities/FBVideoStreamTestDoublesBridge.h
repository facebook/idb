/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

@class FBSimulatorConfiguration;
@class FBSimulatorControlConfiguration;
@class FBSimulatorSet;
@class FBSimulatorVideoStreamFramePusher_VideoToolbox;

NS_ASSUME_NONNULL_BEGIN

/**
 A test double logger that captures all logged messages for assertion.
 */
@interface FBCapturingLogger : NSObject <FBControlCoreLogger>
@property (nonatomic, readonly, strong) NSMutableArray<NSString *> *messages;
@end

/**
 Wraps handleCompressedSampleBuffer:encodeStatus:infoFlags: to accept nullable CMSampleBufferRef.
 Swift cannot pass nil for CMSampleBuffer parameters, so this ObjC wrapper is needed.
 */
void HandleCompressedSampleBufferNullable(
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher,
  CMSampleBufferRef _Nullable sampleBuffer,
  OSStatus encodeStatus,
  VTEncodeInfoFlags infoFlags);

/**
 Creates a FBSimulatorVideoStreamFramePusher_VideoToolbox configured for H264/AnnexB testing.
 This must be in ObjC because the compressorCallback (VTCompressionOutputCallback) and
 frameWriter (FBCompressedFrameWriter) are C function pointers that cannot be easily bridged to Swift.
 */
FBSimulatorVideoStreamFramePusher_VideoToolbox *CreateTestVideoStreamPusher(id<FBControlCoreLogger> logger);

/**
 Creates an FBSimulatorSet using a fake SimDeviceSet (NSObject double).
 SimDeviceSet is a private framework class unavailable in Swift.
 */
FBSimulatorSet *CreateSimulatorSetWithFakeDeviceSet(
  FBSimulatorControlConfiguration *configuration,
  NSObject *fakeDeviceSet);

/**
 Wraps checkRuntimeRequirementsReturningError: because the FBSimulatorConfiguration (CoreSimulator) category
 is not visible in Swift due to forward-declared private framework types (SimDevice, SimRuntime).
 */
BOOL CheckRuntimeRequirements(FBSimulatorConfiguration *configuration, NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
