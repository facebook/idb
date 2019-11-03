/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Encoding of the Bitmap Stream.
 */
typedef NSString *FBBitmapStreamEncoding NS_STRING_ENUM;
extern FBBitmapStreamEncoding const FBBitmapStreamEncodingH264;
extern FBBitmapStreamEncoding const FBBitmapStreamEncodingBGRA;

/**
 A Configuration Object for a Bitmap Stream
 */
@interface FBBitmapStreamConfiguration : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

/**
 The Designated Initializer.

 @param encoding the stream type to use.
 @param framesPerSecond the number of frames per second for an eager stream. nil if a lazy stream.
 */
+ (instancetype)configurationWithEncoding:(FBBitmapStreamEncoding)encoding framesPerSecond:(nullable NSNumber *)framesPerSecond;

/**
 The encoding of the stream.
 */
@property (nonatomic, assign, readonly) FBBitmapStreamEncoding encoding;

/**
 The number of frames per second to use if using an eager stream.
 nil if lazy streaming should be used.
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *framesPerSecond;

@end

NS_ASSUME_NONNULL_END
