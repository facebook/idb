/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Options for FBSimulatorVideo.
 */
typedef NS_OPTIONS(NSUInteger, FBVideoEncoderOptions) {
  FBVideoEncoderOptionsAutorecord = 1 << 0, /** If Set, will automatically start recording when the first video frame is received. **/
  FBVideoEncoderOptionsImmediateFrameStart = 1 << 1, /** If Set, will start recording a video immediately, using the previously delivered frame **/
  FBVideoEncoderOptionsFinalFrame = 1 << 2, /** If Set, will repeat the last frame just before a video is stopped **/
};

/**
 Configuration for the Built In Video Encoder.
 */
@interface FBVideoEncoderConfiguration : NSObject <NSCopying, FBJSONDeserializable, FBJSONSerializable>

#pragma mark Properties

/**
 The Options for the Video Component.
 */
@property (nonatomic, assign, readonly) FBVideoEncoderOptions options;

/**
 The Timescale used in Video Encoding.
 */
@property (nonatomic, assign, readonly) CMTimeScale timescale;

/**
 The Rounding Method used for Video Frames.
 */
@property (nonatomic, assign, readonly) CMTimeRoundingMethod roundingMethod;

/**
 The Default File Path to write to.
 */
@property (nonatomic, copy, readonly) NSString *filePath;

/**
 The FileType of the Video.
 */
@property (nonatomic, nullable, copy, readonly) NSString *fileType;

#pragma mark Defaults & Initializers

/**
 The Default Value of FBFramebufferConfiguration.
 Uses Reasonable Defaults.
 */
+ (instancetype)defaultConfiguration;

/**
 The Default Value of FBFramebufferConfiguration.
 Use this in preference to 'defaultConfiguration' if video encoding is problematic.
 */
+ (instancetype)prudentConfiguration;

#pragma mark Options

/**
 Returns a new Configuration with the Options Applied.
 */
- (instancetype)withOptions:(FBVideoEncoderOptions)options;
+ (instancetype)withOptions:(FBVideoEncoderOptions)options;

#pragma mark Timescale

/**
 Returns a new Configuration with the Timescale Applied.
 */
- (instancetype)withTimescale:(CMTimeScale)timescale;
+ (instancetype)withTimescale:(CMTimeScale)timescale;

#pragma mark Rounding

/**
 Returns a new Configuration with the Rounding Method Applied.
 */
- (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod;
+ (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod;

#pragma mark File Path

/**
 Returns a new Configuration with the diagnostic applied
 */
- (instancetype)withFilePath:(NSString *)filePath;
+ (instancetype)withFilePath:(NSString *)filePath;
- (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic;
+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic;

#pragma mark File Type

/**
 Returns a new Configuration with the File Type Applied.
 */
- (instancetype)withFileType:(NSString *)fileType;
+ (instancetype)withFileType:(NSString *)fileType;

@end

NS_ASSUME_NONNULL_END
