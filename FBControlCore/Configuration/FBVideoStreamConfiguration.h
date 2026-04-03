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
 The rate-control mode for VTCompression.
 */
typedef NS_ENUM(NSUInteger, FBVideoStreamRateControlMode) {
  FBVideoStreamRateControlModeConstantQuality,
  FBVideoStreamRateControlModeAverageBitrate,
};

// FBVideoStreamFormat, FBVideoStreamRateControl, and FBVideoStreamConfiguration classes
// are now implemented in Swift.
// Import FBControlCore/FBControlCore.h or FBControlCore-Swift.h to access them.
