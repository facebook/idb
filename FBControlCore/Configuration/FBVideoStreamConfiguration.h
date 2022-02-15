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
extern FBVideoStreamEncoding const FBVideoStreamEncodingBGRA;
extern FBVideoStreamEncoding const FBVideoStreamEncodingMJPEG;
extern FBVideoStreamEncoding const FBVideoStreamEncodingMinicap;

/**
 A Configuration Object for a Video Stream.
 */
@interface FBVideoStreamConfiguration : NSObject <NSCopying>

/**
 The Designated Initializer.

 @param encoding the stream type to use.
 @param framesPerSecond the number of frames per second for an eager stream. nil if a lazy stream.
 @param compressionQuality the compression quality to use.
 @param scaleFactor the scale factor, between 0-1. nil for no scaling.
 */
- (instancetype)initWithEncoding:(FBVideoStreamEncoding)encoding framesPerSecond:(nullable NSNumber *)framesPerSecond compressionQuality:(nullable NSNumber *)compressionQuality scaleFactor:(nullable NSNumber *)scaleFactor avgBitrate:(nullable NSNumber *)avgBitrate;

/**
 The encoding of the stream.
 */
@property (nonatomic, assign, readonly) FBVideoStreamEncoding encoding;

/**
 The compression quality to use.
 */
@property (nonatomic, copy, readonly) NSNumber *compressionQuality;

/**
 The number of frames per second to use if using an eager stream.
 nil if lazy streaming should be used.
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *framesPerSecond;

/**
 The scale factor between 0-1. nil for no scaling.
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *scaleFactor;

/**
 Average bitrate
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *avgBitrate;

@end

NS_ASSUME_NONNULL_END
