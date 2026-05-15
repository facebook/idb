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
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingH264 NS_SWIFT_NAME(h264);
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingHEVC NS_SWIFT_NAME(hevc);
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingBGRA NS_SWIFT_NAME(bgra);
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingMJPEG NS_SWIFT_NAME(mjpeg);
extern FBVideoStreamEncoding _Nonnull const FBVideoStreamEncodingMinicap;

/**
 The Video Codec for compressed video streams.
 */
typedef NSString *FBVideoStreamCodec NS_STRING_ENUM;
extern FBVideoStreamCodec _Nonnull const FBVideoStreamCodecH264 NS_SWIFT_NAME(h264);
extern FBVideoStreamCodec _Nonnull const FBVideoStreamCodecHEVC NS_SWIFT_NAME(hevc);

/**
 The Transport/Container format for compressed video streams.
 */
typedef NSString *FBVideoStreamTransport NS_STRING_ENUM;
extern FBVideoStreamTransport _Nonnull const FBVideoStreamTransportAnnexB;
extern FBVideoStreamTransport _Nonnull const FBVideoStreamTransportMPEGTS NS_SWIFT_NAME(mpegts);
extern FBVideoStreamTransport _Nonnull const FBVideoStreamTransportFMP4 NS_SWIFT_NAME(fmp4);

/**
 The type of video stream format.
 */
typedef NS_ENUM(NSUInteger, FBVideoStreamFormatType) {
  FBVideoStreamFormatTypeCompressedVideo,
  FBVideoStreamFormatTypeMJPEG NS_SWIFT_NAME(mjpeg),
  FBVideoStreamFormatTypeMinicap,
  FBVideoStreamFormatTypeBGRA NS_SWIFT_NAME(bgra),
};

/**
 The rate-control mode for VTCompression.
 */
typedef NS_ENUM(NSUInteger, FBVideoStreamRateControlMode) {
  FBVideoStreamRateControlModeConstantQuality,
  FBVideoStreamRateControlModeAverageBitrate,
};
