// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
// Test-only header exposing internal classes for unit testing.

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>
#import <FBControlCore/FBControlCore.h>

@class FBVideoStreamConfiguration;

typedef BOOL (*FBCompressedFrameWriter)(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

typedef struct {
    NSUInteger callbackCount;
    NSUInteger writeCount;
    NSUInteger dropCount;
    NSUInteger writeFailureCount;
    NSUInteger encodeErrorCount;
} FBVideoEncoderStats;

@interface FBSimulatorVideoStreamFramePusher_VideoToolbox : NSObject

- (instancetype)initWithConfiguration:(FBVideoStreamConfiguration *)configuration
     compressionSessionProperties:(NSDictionary<NSString *, id> *)compressionSessionProperties
                       videoCodec:(CMVideoCodecType)videoCodec
                         consumer:(id<FBDataConsumer>)consumer
               compressorCallback:(VTCompressionOutputCallback)compressorCallback
                      frameWriter:(FBCompressedFrameWriter)frameWriter
                           logger:(id<FBControlCoreLogger>)logger;

- (void)handleCompressedSampleBuffer:(CMSampleBufferRef)sampleBuffer
                        encodeStatus:(OSStatus)encodeStatus
                           infoFlags:(VTEncodeInfoFlags)infoFlags;

@property (nonatomic, assign) NSUInteger consecutiveNotReadyFrameCount;
@property (nonatomic, assign) BOOL warmupComplete;
@property (nonatomic, assign) BOOL starvationWarningLogged;
@property (nonatomic, assign) FBVideoEncoderStats stats;
@property (nonatomic, assign) FBVideoEncoderStats lastLoggedStats;
@property (nonatomic, assign) CFAbsoluteTime statsStartTime;
@property (nonatomic, assign) CFAbsoluteTime lastStatsLogTime;
@property (nonatomic, assign, readonly) FBCompressedFrameWriter frameWriter;
@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end
