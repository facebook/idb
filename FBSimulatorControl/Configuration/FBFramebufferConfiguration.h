/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBVideoEncoderConfiguration;

/**
 A Configuration Value for a Framebuffer.
 */
@interface FBFramebufferConfiguration : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable, FBDebugDescribeable>

/**
 The Scale of the Framebuffer.
 */
@property (nonatomic, nullable, copy, readonly) FBScale scale;

/**
 The Video Encoder Configuration.
 */
@property (nonatomic, strong, readonly) FBVideoEncoderConfiguration *encoder;

/**
 The Default Image Path to write to.
 */
@property (nonatomic, strong, readonly) NSString *imagePath;

/**
 Creates and Returns a new FBFramebufferConfiguration Value with the provided parameters.

 @param scale the Scale of the Framebuffer.
 @return a FBFramebufferConfiguration instance.
 */
+ (instancetype)configurationWithScale:(nullable FBScale)scale encoder:(FBVideoEncoderConfiguration *)encoder imagePath:(NSString *)imagePath;

/**
 The Default Configuration.
 */
+ (instancetype)defaultConfiguration;

#pragma mark Scale

/**
 Returns a new Configuration with the Scale Applied.
 */
- (instancetype)withScale:(nullable FBScale)scale;
+ (instancetype)withScale:(nullable FBScale)scale;

/**
 The Scale, as a Decimal.
 */
- (nullable NSDecimalNumber *)scaleValue;

/**
 Scales the provided size with the receiver's scale.

 @param size the size to scale.
 @return a scaled size.
 */
- (CGSize)scaleSize:(CGSize)size;

#pragma mark Encoder

/**
 Returns a Configuration with the Encoder Applied.
 */
+ (instancetype)withEncoder:(FBVideoEncoderConfiguration *)encoder;
- (instancetype)withEncoder:(FBVideoEncoderConfiguration *)encoder;

#pragma mark Image Path

/**
 Returns a new Configuration with the Diagnostic Applied.
 */
+ (instancetype)withImagePath:(NSString *)imagePath;
- (instancetype)withImagePath:(NSString *)imagePath;

#pragma mark Simulators

/**
 Returns a new Configuration with the diagnostic paths from the Simulator.
 */
- (instancetype)inSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
