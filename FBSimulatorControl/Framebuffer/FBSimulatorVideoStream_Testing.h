// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
// Test-only header exposing internal classes for unit testing.

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#import <FBControlCore/FBControlCore.h>

#import "FBPeriodicStatsTimer.h"
#import "FBSimulatorVideoStream.h"

NS_ASSUME_NONNULL_BEGIN

@class FBVideoStreamConfiguration;

typedef BOOL (*FBCompressedFrameWriter)(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

@interface FBSimulatorVideoStreamFramePusher_VideoToolbox : NSObject

- (instancetype)initWithConfiguration:(FBVideoStreamConfiguration *)configuration
         compressionSessionProperties:(NSDictionary<NSString *, id> *)compressionSessionProperties
                           videoCodec:(CMVideoCodecType)videoCodec
                             consumer:(id<FBDataConsumer>)consumer
                   compressorCallback:(VTCompressionOutputCallback)compressorCallback
                          frameWriter:(FBCompressedFrameWriter)frameWriter
                   frameWriterContext:(id _Nullable)frameWriterContext
                               logger:(id<FBControlCoreLogger>)logger;

- (void)handleCompressedSampleBuffer:(CMSampleBufferRef)sampleBuffer
                        encodeStatus:(OSStatus)encodeStatus
                           infoFlags:(VTEncodeInfoFlags)infoFlags;

@property (nonatomic, assign) NSUInteger consecutiveNotReadyFrameCount;
@property (nonatomic, assign) BOOL warmupComplete;
@property (nonatomic, assign) BOOL starvationWarningLogged;
@property (nonatomic, assign) FBVideoEncoderStats stats;
@property (nonatomic, assign) FBVideoEncoderStats lastLoggedStats;
@property (nonatomic, assign) FBPeriodicStatsTimer statsTimer;
@property (nonatomic, readonly, assign) FBCompressedFrameWriter frameWriter;
@property (nullable, nonatomic, readonly, strong) id frameWriterContext;
@property (nonatomic, readonly, strong) id<FBDataConsumer> consumer;
@property (nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

@end

NS_ASSUME_NONNULL_END
