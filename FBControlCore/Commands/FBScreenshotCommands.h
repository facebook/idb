/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

/**
 An enum for Screenshot Formats.
 */
typedef NSString *FBScreenshotFormat NS_STRING_ENUM;
extern FBScreenshotFormat _Nonnull const FBScreenshotFormatJPEG;
extern FBScreenshotFormat _Nonnull const FBScreenshotFormatPNG;

@protocol FBScreenshotCommands;
