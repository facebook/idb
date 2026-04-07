/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
// Test-only header exposing internal classes for unit testing.

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#import <FBControlCore/FBControlCore.h>

#import "FBPeriodicStatsTimer.h"
#import "FBSimulatorVideoStream.h"

@class FBVideoStreamConfiguration;

typedef BOOL (*FBCompressedFrameWriter)(CMSampleBufferRef _Nonnull sampleBuffer, id _Nullable context, id<FBDataConsumer> _Nonnull consumer, id<FBControlCoreLogger> _Nonnull logger, NSError * _Nullable * _Nullable error);

@interface FBSimulatorVideoStreamFramePusher_VideoToolbox : NSObject

- (nonnull instancetype)initWithConfiguration:(nonnull FBVideoStreamConfiguration *)configuration
                 compressionSessionProperties:(nonnull NSDictionary<NSString *, id> *)compressionSessionProperties
                                   videoCodec:(CMVideoCodecType)videoCodec
                                     consumer:(nonnull id<FBDataConsumer>)consumer
                           compressorCallback:(VTCompressionOutputCallback _Nonnull)compressorCallback
                                  frameWriter:(FBCompressedFrameWriter _Nonnull)frameWriter
                           frameWriterContext:(id _Nullable)frameWriterContext
                                       logger:(nonnull id<FBControlCoreLogger>)logger;

- (void)handleCompressedSampleBuffer:(CMSampleBufferRef _Nonnull)sampleBuffer
                        encodeStatus:(OSStatus)encodeStatus
                           infoFlags:(VTEncodeInfoFlags)infoFlags;

@property (nonatomic, assign) NSUInteger consecutiveNotReadyFrameCount;
@property (nonatomic, assign) BOOL warmupComplete;
@property (nonatomic, assign) BOOL starvationWarningLogged;
@property (nonatomic, assign) FBVideoEncoderStats stats;
@property (nonatomic, assign) FBVideoEncoderStats lastLoggedStats;
@property (nonatomic, assign) FBPeriodicStatsTimer statsTimer;
@property (nonnull, nonatomic, readonly, assign) FBCompressedFrameWriter frameWriter;
@property (nullable, nonatomic, readonly, strong) id frameWriterContext;
@property (nonnull, nonatomic, readonly, strong) id<FBDataConsumer> consumer;
@property (nonnull, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

@end
