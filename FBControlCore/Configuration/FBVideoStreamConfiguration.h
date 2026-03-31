/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 The Encoding of the Video Stream.
 */
typedef NSString *FBVideoStreamEncoding NS_STRING_ENUM;
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingH264;
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingHEVC;
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingBGRA;
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingMJPEG;
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingMinicap;

/**
 The Video Codec for compressed video streams.
 */
typedef NSString *FBVideoStreamCodec NS_STRING_ENUM;
extern FBVideoStreamCodec _Nonnull const FBVideoStreamCodecH264;
extern FBVideoStreamCodec _Nonnull const FBVideoStreamCodecHEVC;

/**
 The Transport/Container format for compressed video streams.
 */
typedef NSString *FBVideoStreamTransport NS_STRING_ENUM;
extern FBVideoStreamTransport _Nonnull const FBVideoStreamTransportAnnexB;
extern FBVideoStreamTransport _Nonnull const FBVideoStreamTransportMPEGTS;
extern FBVideoStreamTransport _Nonnull const FBVideoStreamTransportFMP4;

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
+ (nonnull instancetype)compressedVideoWithCodec:(nonnull FBVideoStreamCodec)codec
                                       transport:(nonnull FBVideoStreamTransport)transport;
+ (nonnull instancetype)mjpeg;
+ (nonnull instancetype)minicap;
+ (nonnull instancetype)bgra;

@property (nonatomic, readonly, assign) FBVideoStreamFormatType type;
@property (nullable, nonatomic, readonly, copy) FBVideoStreamCodec codec;
@property (nullable, nonatomic, readonly, copy) FBVideoStreamTransport transport;
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
+ (nonnull instancetype)quality:(nonnull NSNumber *)quality;

/**
 Create an average-bitrate rate control.

 @param bitrate the average bitrate in bytes per second.
 */
+ (nonnull instancetype)bitrate:(nonnull NSNumber *)bitrate;

/**
 The rate-control mode.
 */
@property (nonatomic, readonly, assign) FBVideoStreamRateControlMode mode;

/**
 The value: quality (0-1) for constant-quality, bitrate (bytes/sec) for average-bitrate.
 */
@property (nonnull, nonatomic, readonly, copy) NSNumber *value;

@end

/**
 A Configuration Object for a Video Stream.
 */
@interface FBVideoStreamConfiguration : NSObject <NSCopying>

/**
 The Designated Initializer.

 @param format the video stream format to use.
 @param framesPerSecond the number of frames per second for an eager stream. nil if a lazy stream.
 @param rateControl the rate-control mode for VTCompression. nil for default (constant quality 0.75).
 @param scaleFactor the scale factor, between 0-1. nil for no scaling.
 @param keyFrameRate key frame interval in seconds. nil for default (1s).
 */
- (nonnull instancetype)initWithFormat:(nonnull FBVideoStreamFormat *)format framesPerSecond:(nullable NSNumber *)framesPerSecond rateControl:(nullable FBVideoStreamRateControl *)rateControl scaleFactor:(nullable NSNumber *)scaleFactor keyFrameRate:(nullable NSNumber *)keyFrameRate;

/**
 The format of the stream.
 */
@property (nonnull, nonatomic, readonly, copy) FBVideoStreamFormat *format;

/**
 The number of frames per second to use if using an eager stream.
 nil if lazy streaming should be used.
 */
@property (nullable, nonatomic, readonly, copy) NSNumber *framesPerSecond;

/**
 The rate-control mode for VTCompression.
 Always non-nil; defaults to constant-quality at 0.2 if not provided.
 */
@property (nonnull, nonatomic, readonly, copy) FBVideoStreamRateControl *rateControl;

/**
 The scale factor between 0-1. nil for no scaling.
 */
@property (nullable, nonatomic, readonly, copy) NSNumber *scaleFactor;

/**
 Send a key frame every N seconds. Defaults to 1.0 if not provided at init.
 */
@property (nonnull, nonatomic, readonly, copy) NSNumber *keyFrameRate;

@end
