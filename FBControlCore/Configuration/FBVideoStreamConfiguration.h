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
 The type of video stream format.
 */
typedef NS_ENUM(NSUInteger, FBVideoStreamFormatType) {
  FBVideoStreamFormatTypeCompressedVideo,
  FBVideoStreamFormatTypeMJPEG NS_SWIFT_NAME(mjpeg),
  FBVideoStreamFormatTypeMinicap,
  FBVideoStreamFormatTypeBGRA NS_SWIFT_NAME(bgra),
};
