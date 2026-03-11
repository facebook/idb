/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Encoding of the Video Stream.
 */
typedef NSString *FBVideoStreamEncoding NS_STRING_ENUM;
extern FBVideoStreamEncoding const FBVideoStreamEncodingH264;
extern FBVideoStreamEncoding const FBVideoStreamEncodingHEVC;
extern FBVideoStreamEncoding const FBVideoStreamEncodingBGRA;
extern FBVideoStreamEncoding const FBVideoStreamEncodingMJPEG;
extern FBVideoStreamEncoding const FBVideoStreamEncodingMinicap;

/**
 The Video Codec for compressed video streams.
 */
typedef NSString *FBVideoStreamCodec NS_STRING_ENUM;
extern FBVideoStreamCodec const FBVideoStreamCodecH264;
extern FBVideoStreamCodec const FBVideoStreamCodecHEVC;

/**
 The Transport/Container format for compressed video streams.
 */
typedef NSString *FBVideoStreamTransport NS_STRING_ENUM;
extern FBVideoStreamTransport const FBVideoStreamTransportAnnexB;
extern FBVideoStreamTransport const FBVideoStreamTransportMPEGTS;
extern FBVideoStreamTransport const FBVideoStreamTransportFMP4;

/**
 The type of video stream format.
 */
typedef NS_ENUM(NSUInteger, FBVideoStreamFormatType) {
  FBVideoStreamFormatTypeCompressedVideo,
  FBVideoStreamFormatTypeMJPEG,
  FBVideoStreamFormatTypeMinicap,
  FBVideoStreamFormatTypeBGRA,
};

/**
 A tagged union representing the video stream format.
 Compressed video formats compose codec and transport.
 MJPEG, Minicap, and BGRA are fixed presets with no transport axis.
 */
@interface FBVideoStreamFormat : NSObject <NSCopying>
+ (instancetype)compressedVideoWithCodec:(FBVideoStreamCodec)codec
                               transport:(FBVideoStreamTransport)transport;
+ (instancetype)mjpeg;
+ (instancetype)minicap;
+ (instancetype)bgra;

@property (nonatomic, assign, readonly) FBVideoStreamFormatType type;
@property (nonatomic, copy, nullable, readonly) FBVideoStreamCodec codec;
@property (nonatomic, copy, nullable, readonly) FBVideoStreamTransport transport;
@end

/**
 The rate-control mode for VTCompression.
 */
typedef NS_ENUM(NSUInteger, FBVideoStreamRateControlMode) {
  FBVideoStreamRateControlModeConstantQuality,
  FBVideoStreamRateControlModeAverageBitrate,
};

/**
 A tagged union representing VTCompression rate control.
 Either constant-quality (0-1) or average-bitrate (bytes/sec).
 */
@interface FBVideoStreamRateControl : NSObject <NSCopying>

/**
 Create a constant-quality rate control.

 @param quality the quality value between 0 and 1.
 */
+ (instancetype)quality:(NSNumber *)quality;

/**
 Create an average-bitrate rate control.

 @param bitrate the average bitrate in bytes per second.
 */
+ (instancetype)bitrate:(NSNumber *)bitrate;

/**
 The rate-control mode.
 */
@property (nonatomic, assign, readonly) FBVideoStreamRateControlMode mode;

/**
 The value: quality (0-1) for constant-quality, bitrate (bytes/sec) for average-bitrate.
 */
@property (nonatomic, copy, readonly) NSNumber *value;

@end

/**
 A Configuration Object for a Video Stream.
 */
@interface FBVideoStreamConfiguration : NSObject <NSCopying>

/**
 The Designated Initializer.

 @param format the video stream format to use.
 @param framesPerSecond the number of frames per second for an eager stream. nil if a lazy stream.
 @param rateControl the rate-control mode for VTCompression. nil for default (constant quality 0.2).
 @param scaleFactor the scale factor, between 0-1. nil for no scaling.
 @param keyFrameRate key frame interval in seconds. nil for default (1s).
 */
- (instancetype)initWithFormat:(FBVideoStreamFormat *)format framesPerSecond:(nullable NSNumber *)framesPerSecond rateControl:(nullable FBVideoStreamRateControl *)rateControl scaleFactor:(nullable NSNumber *)scaleFactor keyFrameRate:(nullable NSNumber *)keyFrameRate;

/**
 The format of the stream.
 */
@property (nonatomic, copy, readonly) FBVideoStreamFormat *format;

/**
 The number of frames per second to use if using an eager stream.
 nil if lazy streaming should be used.
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *framesPerSecond;

/**
 The rate-control mode for VTCompression.
 Always non-nil; defaults to constant-quality at 0.2 if not provided.
 */
@property (nonatomic, copy, readonly) FBVideoStreamRateControl *rateControl;

/**
 The scale factor between 0-1. nil for no scaling.
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *scaleFactor;

/**
 Send a key frame every N seconds.
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *keyFrameRate;

@end

NS_ASSUME_NONNULL_END
