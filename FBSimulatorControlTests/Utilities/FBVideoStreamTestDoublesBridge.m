/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBVideoStreamTestDoublesBridge.h"

#import <VideoToolbox/VideoToolbox.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorVideoStream_Testing.h>

#pragma mark - FBCapturingLogger

@implementation FBCapturingLogger

- (instancetype)init
{
  self = [super init];
  if (self) {
    _messages = [NSMutableArray array];
  }
  return self;
}

- (id<FBControlCoreLogger>)log:(NSString *)string
{
  [self.messages addObject:string];
  return self;
}

- (id<FBControlCoreLogger>)info { return self; }

- (id<FBControlCoreLogger>)debug { return self; }

- (id<FBControlCoreLogger>)error { return self; }

- (id<FBControlCoreLogger>)withName:(NSString *)prefix { return self; }

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)enabled { return self; }

- (NSString *)name { return nil; }

- (FBControlCoreLogLevel)level { return FBControlCoreLogLevelMultiple; }

@end

#pragma mark - CreateTestVideoStreamPusher

static void TestCompressorCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus encodeStatus, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = (__bridge FBSimulatorVideoStreamFramePusher_VideoToolbox *)(outputCallbackRefCon);
  [pusher handleCompressedSampleBuffer:sampleBuffer encodeStatus:encodeStatus infoFlags:infoFlags];
}

FBSimulatorVideoStreamFramePusher_VideoToolbox *CreateTestVideoStreamPusher(id<FBControlCoreLogger> logger)
{
  FBVideoStreamFormat *format = [FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB];
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
                                        initWithFormat:format
                                        framesPerSecond:@30
                                        rateControl:nil
                                        scaleFactor:nil
                                        keyFrameRate:@10.0];
  id<FBDataConsumer> consumer = [FBDataBuffer accumulatingBuffer];
  return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
          initWithConfiguration:config
          compressionSessionProperties:@{}
          videoCodec:kCMVideoCodecType_H264
          consumer:consumer
          compressorCallback:TestCompressorCallback
          frameWriter:WriteFrameToAnnexBStream
          frameWriterContext:nil
          logger:logger];
}

#pragma mark - CreateSimulatorSetWithFakeDeviceSet

FBSimulatorSet *CreateSimulatorSetWithFakeDeviceSet(FBSimulatorControlConfiguration *configuration,
                                                    NSObject *fakeDeviceSet)
{
  return [FBSimulatorSet setWithConfiguration:configuration
                                    deviceSet:(SimDeviceSet *)fakeDeviceSet
                                     delegate:nil
                                       logger:nil
                                     reporter:nil];
}

#pragma mark - CheckRuntimeRequirements

BOOL CheckRuntimeRequirements(FBSimulatorConfiguration *configuration, NSError * _Nullable * _Nullable error)
{
  return [configuration checkRuntimeRequirementsReturningError:error];
}

#pragma mark - HandleCompressedSampleBufferNullable

void HandleCompressedSampleBufferNullable(FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher,
                                          CMSampleBufferRef _Nullable sampleBuffer,
                                          OSStatus encodeStatus,
                                          VTEncodeInfoFlags infoFlags)
{
  [pusher handleCompressedSampleBuffer:sampleBuffer encodeStatus:encodeStatus infoFlags:infoFlags];
}
